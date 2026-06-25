import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Parameters (set in ignition/parameters/<network>.json):
 *   owner                  - address that receives initial BMMR supply and owns FeeVault + FeeFarm + Pulsar
 *   positionManager        - Uniswap V3 NonfungiblePositionManager address
 *   factory                - Uniswap V3 Factory address
 *   swapRouter             - Uniswap V3 SwapRouter address
 *   wrappedNative          - Wrapped native token address (e.g. WBERA)
 *   targetRatePerLockable  - reward tokens per locked BMMR per epoch (18-decimal fixed point)
 */
export default buildModule("BeemerModule", (m) => {
  const owner                 = m.getParameter("owner");
  const positionManager       = m.getParameter("positionManager");
  const factory               = m.getParameter("factory");
  const swapRouter            = m.getParameter("swapRouter");
  const wrappedNative         = m.getParameter("wrappedNative");
  const targetRatePerLockable = m.getParameter("targetRatePerLockable", 0n);

  const beemer = m.contract("Beemer");

  const feeVault = m.contract("FeeVault", [owner, beemer, wrappedNative]);

  m.call(feeVault, "setTargetRate", [targetRatePerLockable]);

  const feeFarm = m.contract("FeeFarm", [positionManager, factory, feeVault, owner]);

  const pulsar = m.contract("Pulsar", [swapRouter, owner]);

  return { beemer, feeVault, feeFarm, pulsar };
});
