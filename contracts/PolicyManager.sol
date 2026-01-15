// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Call} from "./Types.sol";

contract PolicyManager {
	bytes32 private constant REASON_FROZEN = keccak256("FROZEN");
	bytes32 private constant REASON_TARGET = keccak256("TARGET_NOT_ALLOWED");
	bytes32 private constant REASON_SELECTOR = keccak256("SELECTOR_NOT_ALLOWED");
	bytes32 private constant REASON_DAILY_CAP = keccak256("DAILY_CAP");

	uint256 public constant UNFREEZE_DELAY = 1 days;

	mapping(address => bool) public frozen;
	mapping(address => uint64) public unlockAt;
	mapping(address => bool) public targetAllowlistEnabled;
	mapping(address => bool) public selectorAllowlistEnabled;
	mapping(address => mapping(address => bool)) public allowedTarget;
	mapping(address => mapping(address => mapping(bytes4 => bool))) public allowedSelector;
	mapping(address => mapping(address => uint256)) public capPerDay;
	mapping(address => mapping(address => mapping(uint256 => uint256))) public spentPerDay;

	function setDailyCap(address token, uint256 cap) external {
		capPerDay[msg.sender][token] = cap;
	}

	function setTargetAllowlistEnabled(bool value) external {
		targetAllowlistEnabled[msg.sender] = value;
	}

	function setSelectorAllowlistEnabled(bool value) external {
		selectorAllowlistEnabled[msg.sender] = value;
	}

	function setTargetAllowed(address target, bool allowed) external {
		allowedTarget[msg.sender][target] = allowed;
	}

	function setSelectorAllowed(address target, bytes4 selector, bool allowed) external {
		allowedSelector[msg.sender][target][selector] = allowed;
	}

	function freeze() external {
		frozen[msg.sender] = true;
		unlockAt[msg.sender] = 0;
	}

	function requestUnfreeze() external {
		if (!frozen[msg.sender]) return;
		unlockAt[msg.sender] = uint64(block.timestamp + UNFREEZE_DELAY);
	}

	function unfreeze() external {
		if (!frozen[msg.sender]) return;
		if (unlockAt[msg.sender] == 0) return;
		if (block.timestamp < unlockAt[msg.sender]) return;
		frozen[msg.sender] = false;
		unlockAt[msg.sender] = 0;
	}

	function validateCall(
		address account,
		Call[] calldata calls
	) external view returns (bool ok, bytes32 reason) {
		if (frozen[account]) return (false, REASON_FROZEN);
		if (!_validateTargets(account, calls)) return (false, REASON_TARGET);
		if (!_validateSelectors(account, calls)) return (false, REASON_SELECTOR);
		if (!_validateDailyCap(account, calls)) return (false, REASON_DAILY_CAP);
		return (true, bytes32(0));
	}

	function postExec(address account, Call[] calldata calls) external {
		if (msg.sender != account) return;
		uint256 totalValue = _totalValue(calls);
		if (totalValue == 0) return;
		uint256 cap = capPerDay[account][address(0)];
		if (cap == 0) return;
		uint256 day = block.timestamp / 1 days;
		uint256 spent = spentPerDay[account][address(0)][day];
		spentPerDay[account][address(0)][day] = spent + totalValue;
	}

	function _validateTargets(address account, Call[] calldata calls) internal view returns (bool) {
		if (!targetAllowlistEnabled[account]) return true;
		for (uint256 i = 0; i < calls.length; i++) {
			if (!allowedTarget[account][calls[i].target]) return false;
		}
		return true;
	}

	function _validateSelectors(address account, Call[] calldata calls) internal view returns (bool) {
		if (!selectorAllowlistEnabled[account]) return true;
		for (uint256 i = 0; i < calls.length; i++) {
			bytes4 selector = _selector(calls[i].data);
			if (!allowedSelector[account][calls[i].target][selector]) return false;
		}
		return true;
	}

	function _validateDailyCap(address account, Call[] calldata calls) internal view returns (bool) {
		uint256 cap = capPerDay[account][address(0)];
		if (cap == 0) return true;
		uint256 totalValue = _totalValue(calls);
		if (totalValue == 0) return true;
		uint256 day = block.timestamp / 1 days;
		uint256 spent = spentPerDay[account][address(0)][day];
		return spent + totalValue <= cap;
	}

	function _totalValue(Call[] calldata calls) internal pure returns (uint256 total) {
		for (uint256 i = 0; i < calls.length; i++) {
			total += calls[i].value;
		}
	}

	function _selector(bytes calldata data) internal pure returns (bytes4) {
		if (data.length < 4) return bytes4(0);
		return bytes4(data[:4]);
	}
}
