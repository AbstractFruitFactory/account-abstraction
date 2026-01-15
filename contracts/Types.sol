// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct UserOperation {
	address sender;
	uint256 nonce;
	bytes initCode;
	bytes callData;
	uint256 callGasLimit;
	uint256 verificationGasLimit;
	uint256 preVerificationGas;
	uint256 maxFeePerGas;
	uint256 maxPriorityFeePerGas;
	bytes paymasterAndData;
	bytes signature;
}

struct Call {
	address target;
	uint256 value;
	bytes data;
}

interface IEntryPoint {
	function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32);
	function depositTo(address account) external payable;
}
