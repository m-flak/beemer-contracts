import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.create();

const RATE = 1_000_000_000_000n; // 1e12 — 0.000001 reward token per locked BMMR
const LOCKED = 250_000_000n * 10n ** 18n; // 250M BMMR

async function deployFixture() {
  const [owner] = await ethers.getSigners();

  const beemer  = await ethers.deployContract("Beemer");
  const feeVault = await ethers.deployContract("FeeVault", [owner.address, await beemer.getAddress()]);

  await feeVault.setTargetRate(RATE);
  await beemer.lock(ethers.encodeBytes32String("VESTING"), LOCKED, 365 * 24 * 3600);

  return { beemer, feeVault };
}

describe("FeeVault", function () {
  describe("recommendedSeed", function () {
    it("returns 250 WBERA shortfall for 250M locked BMMR at 1e12 rate", async function () {
      const { beemer, feeVault } = await networkHelpers.loadFixture(deployFixture);

      const seed = await feeVault.recommendedSeed(await beemer.getAddress());

      // 250_000_000e18 * 1e12 / 1e18 = 250e18
      expect(seed).to.equal(ethers.parseEther("250"));
    });

    it("returns zero when vault already holds enough", async function () {
      const { beemer, feeVault } = await networkHelpers.loadFixture(deployFixture);

      // Fund the vault with exactly the needed amount
      await beemer.transfer(await feeVault.getAddress(), ethers.parseEther("250"));

      const seed = await feeVault.recommendedSeed(await beemer.getAddress());
      expect(seed).to.equal(0n);
    });

    it("returns the shortfall when vault is partially funded", async function () {
      const { beemer, feeVault } = await networkHelpers.loadFixture(deployFixture);

      await beemer.transfer(await feeVault.getAddress(), ethers.parseEther("100"));

      const seed = await feeVault.recommendedSeed(await beemer.getAddress());
      expect(seed).to.equal(ethers.parseEther("150"));
    });
  });
});
