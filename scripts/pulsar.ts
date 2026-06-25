import { network } from "hardhat";
import type { Log, LogDescription } from "ethers";

const { ethers } = await network.getOrCreate();

const PULSAR_ADDRESS     = process.env.PULSAR_ADDRESS     ?? "";
const BMMR_ADDRESS       = process.env.BMMR_ADDRESS       ?? "";
const TOTAL_AMOUNT       = BigInt(process.env.TOTAL_AMOUNT       ?? "0");
const AMOUNT_PER_SWAPPER = BigInt(process.env.AMOUNT_PER_SWAPPER ?? "0");
const ZERO_FOR_ONE       = process.env.ZERO_FOR_ONE === "true";
const SLIPPAGE_BPS       = BigInt(process.env.SLIPPAGE_BPS ?? "500");
const GAS_ETH_PER_EOA    = ethers.parseEther(process.env.GAS_ETH_PER_EOA ?? "0.00001");

async function main() {
  if (!PULSAR_ADDRESS)           throw new Error("PULSAR_ADDRESS env var required");
  if (!BMMR_ADDRESS)             throw new Error("BMMR_ADDRESS env var required");
  if (TOTAL_AMOUNT === 0n)       throw new Error("TOTAL_AMOUNT env var required");
  if (AMOUNT_PER_SWAPPER === 0n) throw new Error("AMOUNT_PER_SWAPPER env var required");

  const [signer] = await ethers.getSigners();
  const pulsar   = await ethers.getContractAt("Pulsar", PULSAR_ADDRESS, signer);
  const count    = TOTAL_AMOUNT / AMOUNT_PER_SWAPPER;

  // 0. Transfer BMMR to Pulsar
  const bmmr = new ethers.Contract(BMMR_ADDRESS, ["function transfer(address to, uint256 amount) returns (bool)"], signer);
  console.log(`Transferring ${ethers.formatEther(TOTAL_AMOUNT)} BMMR to Pulsar...`);
  await (await bmmr.transfer(PULSAR_ADDRESS, TOTAL_AMOUNT)).wait();

  // 1. Deploy swappers
  console.log(`Deploying ${count} swapper(s)...`);
  const tx      = await pulsar.pulse(TOTAL_AMOUNT, AMOUNT_PER_SWAPPER, ZERO_FOR_ONE, SLIPPAGE_BPS);
  const receipt = await tx.wait();
  if (!receipt) throw new Error("No receipt for pulse() tx");

  const parsed = receipt.logs
    .map((log: Log) => { try { return pulsar.interface.parseLog(log); } catch { return null; } })
    .find((e: LogDescription | null) => e?.name === "Pulsed");
  if (!parsed) throw new Error("Pulsed event not found");
  const swapperAddresses: string[] = parsed.args.swappers;
  console.log(`Swappers: ${swapperAddresses.join(", ")}`);

  // 2. Roll one random EOA per swapper
  const eoas = swapperAddresses.map(() => ethers.Wallet.createRandom(ethers.provider));

  // 3. Fund each EOA for gas — parallel with explicit nonces (all from same signer)
  console.log(`Funding ${eoas.length} EOA(s) with ${ethers.formatEther(GAS_ETH_PER_EOA)} ETH each...`);
  const baseNonce = await signer.getNonce();
  await Promise.all(
    eoas.map((eoa, i) =>
      signer
        .sendTransaction({ to: eoa.address, value: GAS_ETH_PER_EOA, nonce: baseNonce + i })
        .then(t => t.wait()),
    ),
  );

  // 4. Execute each swapper sequentially to avoid cumulative price impact
  console.log("Executing swappers...");
  for (let i = 0; i < swapperAddresses.length; i++) {
    const addr    = swapperAddresses[i];
    const swapper = await ethers.getContractAt("Swapper", addr, eoas[i]);
    let stx;
    try {
      stx = await swapper.execute();
    } catch (e: any) {
      console.error(`  ${addr} execute() reverted:`, JSON.stringify(e, Object.getOwnPropertyNames(e), 2));
      throw e;
    }
    const srec = await stx.wait();
    console.log(`  ${addr} → tx ${srec?.hash}`);
  }

  // 5. Sweep remaining ETH from each EOA back to the signer
  console.log("Sweeping dust back to signer...");
  const feeData        = await ethers.provider.getFeeData();
  const maxFeePerGas   = feeData.maxFeePerGas ?? feeData.gasPrice ?? 0n;
  const transferGasCost = 21_000n * maxFeePerGas;

  await Promise.all(
    eoas.map(async eoa => {
      const balance  = await ethers.provider.getBalance(eoa.address);
      const sendable = balance - transferGasCost;
      if (sendable <= 0n) return;
      const stx = await eoa.sendTransaction({
        to: signer.address,
        value: sendable,
        gasLimit: 21_000n,
        maxFeePerGas,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas ?? 0n,
      });
      await stx.wait();
      console.log(`  ${eoa.address}: swept ${ethers.formatEther(sendable)} ETH`);
    }),
  );

  console.log("Done.");
}

main().catch(e => { console.error(e); process.exit(1); });
