import { network } from "hardhat";

const { ethers } = await network.getOrCreate();
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const BEEMER_ADDRESS    = process.env.BEEMER_ADDRESS    ?? "";
const FEE_VAULT_ADDRESS = process.env.FEE_VAULT_ADDRESS ?? "";
const REWARD_TOKEN      = process.env.REWARD_TOKEN      ?? "";
const FROM_BLOCK        = process.env.FROM_BLOCK ? parseInt(process.env.FROM_BLOCK) : 0;

async function uploadToPinata(epochId: bigint, tree: StandardMerkleTree<[string, bigint]>): Promise<string> {
  const res = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${process.env.PINATA_JWT}`,
    },
    body: JSON.stringify({
      pinataContent: tree.dump(),
      pinataMetadata: { name: `beemer-epoch-${epochId}.json` },
    }, (_, v) => typeof v === "bigint" ? v.toString() : v),
  });

  if (!res.ok) throw new Error(`Pinata upload failed: ${await res.text()}`);
  const { IpfsHash } = await res.json() as { IpfsHash: string };
  return `ipfs://${IpfsHash}`;
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
  if (!BEEMER_ADDRESS)    throw new Error("BEEMER_ADDRESS env var required");
  if (!FEE_VAULT_ADDRESS) throw new Error("FEE_VAULT_ADDRESS env var required");
  if (!REWARD_TOKEN)      throw new Error("REWARD_TOKEN env var required");
  if (!process.env.PINATA_JWT) throw new Error("PINATA_JWT env var required");
  if (!FROM_BLOCK)        throw new Error("FROM_BLOCK env var required");

  const [signer] = await ethers.getSigners();
  const beemer   = await ethers.getContractAt("Beemer",   BEEMER_ADDRESS,    signer);
  const feeVault = await ethers.getContractAt("FeeVault", FEE_VAULT_ADDRESS, signer);
  const token    = new ethers.Contract(REWARD_TOKEN, ["function balanceOf(address) view returns (uint256)"], signer);

  // ── 1. Find all addresses that have ever had tokens locked ────────────────
  const snapshotBlock = await ethers.provider.getBlockNumber();
  const events  = await queryFilterPaginated(beemer, beemer.filters.Locked(), FROM_BLOCK, snapshotBlock);
  const lockers = [...new Set(events.map((e: any) => e.args._of as string))];
  console.log(`Found ${lockers.length} unique lockers.`);

  // ── 2. Snapshot locked balances at the current block ─────────────────────
  console.log(`Snapshotting at block ${snapshotBlock}`);

  const entries: { address: string; locked: bigint }[] = [];
  let totalLocked = 0n;

  for (const locker of lockers) {
    const opts         = { blockTag: snapshotBlock };
    const totalBalance = await beemer.totalBalanceOf(locker, opts);
    const freeBalance  = await beemer.balanceOf(locker, opts);
    const locked       = totalBalance - freeBalance;
    if (locked > 0n) {
      entries.push({ address: locker, locked });
      totalLocked += locked;
    }
  }

  if (totalLocked === 0n) { console.log("No BMMR locked — skipping."); return; }
  console.log(`Total locked BMMR: ${ethers.formatEther(totalLocked)}`);

  // ── 3. How much reward token is sitting in the vault? ────────────────────
  const vaultBalance = await token.balanceOf(FEE_VAULT_ADDRESS, { blockTag: snapshotBlock });
  if (vaultBalance === 0n) { console.log("No rewards in vault — skipping."); return; }
  console.log(`Vault balance: ${ethers.formatEther(vaultBalance)}`);

  // ── 4. Compute pro-rata rewards ───────────────────────────────────────────
  const leaves: [string, bigint][] = entries.map(({ address, locked }) => [
    address,
    (locked * vaultBalance) / totalLocked,
  ]);

  // Use the sum of computed rewards (not vaultBalance) so dust stays in the vault.
  const epochAmount = leaves.reduce((sum, [, r]) => sum + r, 0n);
  console.log(`Epoch total (post-dust trim): ${ethers.formatEther(epochAmount)}`);

  // ── 5. Build Merkle tree ──────────────────────────────────────────────────
  const tree    = StandardMerkleTree.of(leaves, ["address", "uint256"]);
  const epochId = await feeVault.epochCount();
  console.log(`Merkle root: ${tree.root}`);

  // ── 6. Upload tree to IPFS via Pinata ────────────────────────────────────
  const treeUri = await uploadToPinata(epochId, tree);
  console.log(`Tree pinned at ${treeUri}`);

  // ── 7. Create the epoch on-chain ─────────────────────────────────────────
  const tx      = await feeVault.createEpoch(REWARD_TOKEN, epochAmount, tree.root, treeUri);
  const receipt = await tx.wait();
  console.log(`Epoch ${epochId} created in tx ${receipt?.hash}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
