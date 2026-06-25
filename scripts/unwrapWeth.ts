import { network } from "hardhat";

const { ethers } = await network.getOrCreate();

//const WETH_ADDRESS = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14";
const WETH_ADDRESS = "0x6969696969696969696969696969696969696969";
const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function withdraw(uint256 amount)",
];

async function main() {
  const [signer] = await ethers.getSigners();
  const weth     = new ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);

  const balance: bigint = await weth.balanceOf(signer.address);
  if (balance === 0n) { console.log("No WETH to unwrap."); return; }

  console.log(`Unwrapping ${ethers.formatEther(balance)} WETH...`);
  await (await weth.withdraw(balance)).wait();
  console.log("Done.");
}

main().catch(e => { console.error(e); process.exit(1); });
