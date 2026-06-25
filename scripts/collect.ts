import { network } from "hardhat";

const { ethers } = await network.getOrCreate();

const FEE_FARM_ADDRESS = process.env.FEE_FARM_ADDRESS ?? "";
const PP_KEY           = process.env.PP_KEY           ?? "";

async function main() {
  if (!FEE_FARM_ADDRESS) throw new Error("FEE_FARM_ADDRESS env var required");
  if (!PP_KEY)           throw new Error("PP_KEY env var required");

  const [signer] = await ethers.getSigners();
  const feeFarm  = await ethers.getContractAt("FeeFarm", FEE_FARM_ADDRESS, signer);

  console.log(`Collecting fees for pool ${PP_KEY}...`);
  const tx      = await feeFarm.collect(PP_KEY);
  const receipt = await tx.wait();

  const event = receipt?.logs
    .map(log => { try { return feeFarm.interface.parseLog(log); } catch { return null; } })
    .find(e => e?.name === "FeesCollected");

  if (!event) {
    console.log("No fees collected.");
  } else {
    console.log(`Collected: ${ethers.formatEther(event.args.amount0)} token0, ${ethers.formatEther(event.args.amount1)} token1`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
