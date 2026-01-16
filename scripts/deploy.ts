import { network } from "hardhat";

const entryPoint = process.env.ENTRYPOINT_ADDRESS as `0x${string}` | undefined;
const ownerOverride = process.env.OWNER_ADDRESS as `0x${string}` | undefined;

if (!entryPoint) {
  throw new Error("ENTRYPOINT_ADDRESS is required");
}

const { viem } = await network.connect({
  network: "arbitrumSepolia",
  chainType: "l1",
});

const publicClient = await viem.getPublicClient();
const [deployer] = await viem.getWalletClients();
const owner = ownerOverride ?? deployer.account.address;

console.log("Deployer:", deployer.account.address);
console.log("Owner:", owner);
console.log("EntryPoint:", entryPoint);

const policyManager = await viem.deployContract("PolicyManager");
const sessionKeyManager = await viem.deployContract("SessionKeyManager");
const smartAccount = await viem.deployContract("SmartAccount", [
  owner,
  entryPoint,
  policyManager.address,
  sessionKeyManager.address,
]);

const policyReceipt = await publicClient.waitForTransactionReceipt({
  hash: policyManager.deploymentTransaction.hash,
});
const sessionReceipt = await publicClient.waitForTransactionReceipt({
  hash: sessionKeyManager.deploymentTransaction.hash,
});
const smartReceipt = await publicClient.waitForTransactionReceipt({
  hash: smartAccount.deploymentTransaction.hash,
});

console.log("PolicyManager:", policyManager.address, policyReceipt.transactionHash);
console.log("SessionKeyManager:", sessionKeyManager.address, sessionReceipt.transactionHash);
console.log("SmartAccount:", smartAccount.address, smartReceipt.transactionHash);
