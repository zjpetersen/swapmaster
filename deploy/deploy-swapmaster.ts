import { utils, Provider, Wallet } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment, HttpNetworkConfig } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";

const USDC_ADDR = "0x3355df6D4c9C3035724Fd0e3914dE96A5a83aaf4"

export default async function (hre: HardhatRuntimeEnvironment) {
    console.log((hre.network.config as HttpNetworkConfig).url)
  const provider = new Provider((hre.network.config as HttpNetworkConfig).url);

  // The wallet that will deploy the token and the paymaster
  // It is assumed that this wallet already has sufficient funds on zkSync
  const wallet = new Wallet("0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110");

  const deployer = new Deployer(hre, wallet);

  // Deploying the paymaster
  const paymasterArtifact = await deployer.loadArtifact("Swapmaster");
  const paymaster = await deployer.deploy(paymasterArtifact);
  console.log(`Paymaster address: ${paymaster.address}`);

  console.log("Funding paymaster with ETH");
  // Supplying paymaster with ETH
  // await (
  //   await deployer.zkWallet.sendTransaction({
  //     to: paymaster.address,
  //     value: ethers.utils.parseEther("10"),
  //   })
  // ).wait();

  let paymasterBalance = await provider.getBalance(paymaster.address);

  console.log(`Paymaster ETH balance is now ${paymasterBalance.toString()}`);

  console.log(`Done!`);
}
