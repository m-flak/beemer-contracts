import { network } from "hardhat";

const { ethers } = await network.getOrCreate();

const FEE_FARM_ADDRESS = process.env.FEE_FARM_ADDRESS ?? "";

async function main() {
  if (!FEE_FARM_ADDRESS) throw new Error("FEE_FARM_ADDRESS env var required");

  const feeFarm = await ethers.getContractAt("FeeFarm", FEE_FARM_ADDRESS);
  const keys    = await feeFarm.getPoolKeys();

  if (keys.length === 0) {
    console.log("No pools registered.");
    return;
  }

  for (const key of keys) {
    const p = await feeFarm.getPoolPosition(key);

    const erc20MetaAbi = ["function symbol() view returns (string)", "function decimals() view returns (uint8)"];
    const token0 = new ethers.Contract(p.token0, erc20MetaAbi, ethers.provider);
    const token1 = new ethers.Contract(p.token1, erc20MetaAbi, ethers.provider);
    const [sym0, dec0] = await Promise.all([token0.symbol(), token0.decimals()]);
    const [sym1, dec1] = await Promise.all([token1.symbol(), token1.decimals()]);

    console.log(`\nPool: ${p.pool}`);
    console.log(`  Key:          ${key}`);
    console.log(`  Token0:       ${p.token0} (${sym0})`);
    console.log(`  Token1:       ${p.token1} (${sym1})`);
    console.log(`  Fee:          ${Number(p.poolFee) / 10_000}%`);
    console.log(`  Positions:    ${p.positionTokenIds.length === 0 ? "none" : p.positionTokenIds.map(String).join(", ")}`);
    console.log(`  Total fees collected:`);
    console.log(`    ${sym0}: ${ethers.formatUnits(p.totalCollected0, dec0)}`);
    console.log(`    ${sym1}: ${ethers.formatUnits(p.totalCollected1, dec1)}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
