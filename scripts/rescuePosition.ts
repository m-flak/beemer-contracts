import { network } from "hardhat";

const { ethers } = await network.getOrCreate();

const FEE_FARM_ADDRESS = process.env.FEE_FARM_ADDRESS ?? "";
const TOKEN_ID         = BigInt(process.env.TOKEN_ID ?? "0");
const RECIPIENT        = process.env.RECIPIENT ?? "";

async function main() {
  if (!FEE_FARM_ADDRESS) throw new Error("FEE_FARM_ADDRESS env var required");
  if (!TOKEN_ID)         throw new Error("TOKEN_ID env var required");
  if (!RECIPIENT)        throw new Error("RECIPIENT env var required");

  const [signer] = await ethers.getSigners();
  const feeFarm  = await ethers.getContractAt("FeeFarm", FEE_FARM_ADDRESS, signer);

  console.log(`Rescuing position ${TOKEN_ID} → ${RECIPIENT}...`);
  await (await feeFarm.rescuePosition(TOKEN_ID, RECIPIENT)).wait();
  console.log("Done.");
}

main().catch(e => { console.error(e); process.exit(1); });
