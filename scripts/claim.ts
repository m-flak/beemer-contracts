import { network } from "hardhat";

const { ethers } = await network.getOrCreate();
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const FEE_VAULT_ADDRESS = process.env.FEE_VAULT_ADDRESS ?? "";
const FROM_BLOCK        = process.env.FROM_BLOCK ? parseInt(process.env.FROM_BLOCK) : 0;

async function fetchTree(treeUri: string): Promise<StandardMerkleTree<[string, bigint]>> {
  const url = treeUri.replace("ipfs://", "https://gateway.pinata.cloud/ipfs/");
  const res  = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch tree: ${treeUri}`);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return StandardMerkleTree.load(await res.json() as any);
}

async function queryFilterPaginated<T>(
  contract: any,
  filter: any,
  fromBlock: number,
  toBlock: number,
  chunkSize = 2000,
): Promise<T[]> {
  const results: T[] = [];
  for (let start = fromBlock; start <= toBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, toBlock);
    const chunk = await contract.queryFilter(filter, start, end);
    results.push(...chunk);
  }
  return results;
}

async function main() {
  if (!FEE_VAULT_ADDRESS) throw new Error("FEE_VAULT_ADDRESS env var required");
  if (!FROM_BLOCK)        throw new Error("FROM_BLOCK env var required");

  const [signer] = await ethers.getSigners();
  const userAddress = await signer.getAddress();
  const feeVault    = await ethers.getContractAt("FeeVault", FEE_VAULT_ADDRESS, signer);

  // ── 1. Discover all epochs from EpochCreated events ──────────────────────
  const toBlock = await ethers.provider.getBlockNumber();
  const events  = await queryFilterPaginated(feeVault, feeVault.filters.EpochCreated(), FROM_BLOCK, toBlock);
  console.log(`Found ${events.length} epoch(s).`);

  let totalClaimed = 0n;

  for (const event of events) {
    const { epochId, token, treeUri } = (event as any).args;

    // ── 2. Skip already-claimed epochs ─────────────────────────────────────
    if (await feeVault.claimed(userAddress, epochId)) {
      console.log(`Epoch ${epochId}: already claimed, skipping.`);
      continue;
    }

    // ── 3. Fetch the Merkle tree from IPFS ──────────────────────────────────
    let tree: StandardMerkleTree<[string, bigint]>;
    try {
      tree = await fetchTree(treeUri);
    } catch (e) {
      console.warn(`Epoch ${epochId}: could not fetch tree (${treeUri}), skipping.`);
      continue;
    }

    // ── 4. Find the user's leaf and generate a proof ─────────────────────
    let found = false;
    for (const [i, [address, amount]] of tree.entries()) {
      if (address.toLowerCase() !== userAddress.toLowerCase()) continue;

      const proof = tree.getProof(i);
      console.log(`Epoch ${epochId}: claiming ${ethers.formatEther(amount)} of token ${token}`);

      const tx      = await feeVault.claim(epochId, amount, proof);
      const receipt = await tx.wait();
      console.log(`  ✔ claimed in tx ${receipt?.hash}`);

      totalClaimed += amount;
      found = true;
      break;
    }

    if (!found) console.log(`Epoch ${epochId}: no allocation for ${userAddress}.`);
  }

  console.log(`\nDone. Total claimed this run: ${ethers.formatEther(totalClaimed)}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
