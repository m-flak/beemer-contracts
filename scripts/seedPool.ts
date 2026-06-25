import { network } from "hardhat";

const { ethers } = await network.getOrCreate();

const POSITION_MANAGER = process.env.POSITION_MANAGER ?? "";
const FEE_FARM_ADDRESS = process.env.FEE_FARM_ADDRESS ?? "";
const BMMR_ADDRESS     = process.env.BMMR_ADDRESS     ?? "";
//const WETH_ADDRESS     = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14";
const WETH_ADDRESS     = "0x6969696969696969696969696969696969696969"
const POOL_FEE         = Number(process.env.POOL_FEE ?? "3000");

const WETH_AMOUNT = ethers.parseEther("0.5");
const BMMR_AMOUNT = ethers.parseUnits("50000000", 18);

const TICK_SPACINGS: Record<number, number> = { 500: 10, 3000: 60, 10000: 200 };

function sqrtBigInt(n: bigint): bigint {
  if (n === 0n) return 0n;
  let x = n, y = (n + 1n) / 2n;
  while (y < x) { x = y; y = (n / y + y) / 2n; }
  return x;
}

// sqrt(amount1/amount0) * 2^96, using integer arithmetic
function encodeSqrtPriceX96(amount1: bigint, amount0: bigint): bigint {
  return sqrtBigInt((amount1 * (1n << 192n)) / amount0);
}

function fullRangeTicks(fee: number): [number, number] {
  const spacing = TICK_SPACINGS[fee];
  if (!spacing) throw new Error(`Unknown fee tier: ${fee}`);
  const bound = Math.floor(887272 / spacing) * spacing;
  return [-bound, bound];
}

const ERC20_ABI = ["function approve(address spender, uint256 amount) returns (bool)"];

const WETH_ABI = [
  ...ERC20_ABI,
  "function deposit() payable",
];

const NPM_ABI = [
  "function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) payable returns (address pool)",
  "function mint(tuple(address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline) params) payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)",
  "function safeTransferFrom(address from, address to, uint256 tokenId)",
];

async function main() {
  if (!POSITION_MANAGER) throw new Error("POSITION_MANAGER env var required");
  if (!FEE_FARM_ADDRESS)  throw new Error("FEE_FARM_ADDRESS env var required");
  if (!BMMR_ADDRESS)      throw new Error("BMMR_ADDRESS env var required");

  const [signer] = await ethers.getSigners();
  const weth    = new ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);
  const bmmr    = new ethers.Contract(BMMR_ADDRESS, ERC20_ABI, signer);
  const npm     = new ethers.Contract(POSITION_MANAGER, NPM_ABI, signer);
  const feeFarm = await ethers.getContractAt("FeeFarm", FEE_FARM_ADDRESS, signer);

  // Uniswap requires token0 < token1 by address
  const bmmrFirst = BigInt(BMMR_ADDRESS) < BigInt(WETH_ADDRESS);
  const [token0, token1, amount0Desired, amount1Desired] = bmmrFirst
    ? [BMMR_ADDRESS, WETH_ADDRESS, BMMR_AMOUNT, WETH_AMOUNT]
    : [WETH_ADDRESS, BMMR_ADDRESS, WETH_AMOUNT, BMMR_AMOUNT];

  const sqrtPriceX96 = encodeSqrtPriceX96(amount1Desired, amount0Desired);
  const [tickLower, tickUpper] = fullRangeTicks(POOL_FEE);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 900);

  console.log(`Token0:       ${token0}`);
  console.log(`Token1:       ${token1}`);
  console.log(`Fee:          ${POOL_FEE}`);
  console.log(`Ticks:        [${tickLower}, ${tickUpper}]`);
  console.log(`sqrtPriceX96: ${sqrtPriceX96}`);

  // 1. Wrap ETH → WETH
  console.log("\n[1/6] Wrapping 1.0 ETH → WETH...");
  await (await weth.deposit({ value: WETH_AMOUNT })).wait();

  // 2. Approve positionManager for WETH (sequential: same signer nonce queue)
  console.log("[2/6] Approving WETH...");
  await (await weth.approve(POSITION_MANAGER, WETH_AMOUNT)).wait();

  // 3. Approve positionManager for BMMR
  console.log("[3/6] Approving BMMR...");
  await (await bmmr.approve(POSITION_MANAGER, BMMR_AMOUNT)).wait();

  // 4. Create and initialize pool, then staticCall to read back the address (pool now exists, no revert)
  console.log(`[4/6] Creating pool...`);
  try {
    await (await npm.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, sqrtPriceX96)).wait();
  } catch (e: any) {
    console.error("createAndInitializePoolIfNecessary reverted:");
    console.error("  message:", e.message);
    console.error("  reason: ", e.reason);
    console.error("  data:   ", e.data);
    throw e;
  }
  const poolAddress: string = await npm.createAndInitializePoolIfNecessary.staticCall(
    token0, token1, POOL_FEE, 0,
  );
  console.log(`  Pool: ${poolAddress}`);

  // 5. Mint full-range position (staticCall first to capture tokenId)
  const mintParams = {
    token0, token1,
    fee: POOL_FEE,
    tickLower, tickUpper,
    amount0Desired, amount1Desired,
    amount0Min: 0n,
    amount1Min: 0n,
    recipient: signer.address,
    deadline,
  };
  const [tokenId]: bigint[] = await npm.mint.staticCall(mintParams);
  console.log(`[5/6] Minting full-range position (tokenId=${tokenId})...`);
  await (await npm.mint(mintParams)).wait();

  // 6. Register pool with FeeFarm and transfer the NFT to it
  console.log("[6/6] Registering pool and transferring NFT to FeeFarm...");
  await (await feeFarm.addPool(poolAddress)).wait();
  await (await npm.safeTransferFrom(signer.address, FEE_FARM_ADDRESS, tokenId)).wait();

  console.log("\nDone.");
  console.log(`  Pool:    ${poolAddress}`);
  console.log(`  TokenId: ${tokenId}`);
}

main().catch(e => { console.error(e); process.exit(1); });
