// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Call} from "./Types.sol";

contract SessionKeyManager {
	using ECDSA for bytes32;
	using MessageHashUtils for bytes32;

	struct Session {
		uint64 validAfter;
		uint64 validUntil;
		uint256 maxValuePerTx;
		bool enabled;
		bool targetAllowlistEnabled;
		bool selectorAllowlistEnabled;
	}

	struct SessionConfig {
		uint64 validAfter;
		uint64 validUntil;
		uint256 maxValuePerTx;
		bool targetAllowlistEnabled;
		bool selectorAllowlistEnabled;
	}

	event SessionKeyCreated(address indexed account, address indexed sessionKey, uint64 validUntil, bytes32 scopeHash);
	event SessionKeyRevoked(address indexed account, address indexed sessionKey);

	mapping(address => mapping(address => Session)) private sessions;
	mapping(address => mapping(address => mapping(address => bool))) private allowedTarget;
	mapping(address => mapping(address => mapping(address => mapping(bytes4 => bool)))) private allowedSelector;

	function createSessionKey(
		address sessionKey,
		SessionConfig calldata cfg,
		address[] calldata targets,
		bytes4[][] calldata selectors
	) external {
		if (targets.length != selectors.length) revert();
		sessions[msg.sender][sessionKey] = Session({
			validAfter: cfg.validAfter,
			validUntil: cfg.validUntil,
			maxValuePerTx: cfg.maxValuePerTx,
			enabled: true,
			targetAllowlistEnabled: cfg.targetAllowlistEnabled,
			selectorAllowlistEnabled: cfg.selectorAllowlistEnabled
		});
		for (uint256 i = 0; i < targets.length; i++) {
			allowedTarget[msg.sender][sessionKey][targets[i]] = true;
			for (uint256 j = 0; j < selectors[i].length; j++) {
				allowedSelector[msg.sender][sessionKey][targets[i]][selectors[i][j]] = true;
			}
		}
		emit SessionKeyCreated(msg.sender, sessionKey, cfg.validUntil, _scopeHash(cfg, targets, selectors));
	}

	function revokeSessionKey(address sessionKey) external {
		sessions[msg.sender][sessionKey].enabled = false;
		emit SessionKeyRevoked(msg.sender, sessionKey);
	}

	function isSessionKeyValid(
		address account,
		bytes32 userOpHash,
		bytes calldata signature,
		Call[] calldata calls,
		uint256 _totalValue
	) external view returns (bool ok, bytes32 reason) {
		_totalValue;
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		address signer = digest.recover(signature);
		Session memory session = sessions[account][signer];
		if (!session.enabled) return (false, keccak256("SESSION_DISABLED"));
		if (!_isTimeValid(session)) return (false, keccak256("SESSION_TIME"));
		if (!_isScopeValid(account, signer, session, calls)) return (false, keccak256("SESSION_SCOPE"));
		if (!_isValueValid(session, calls)) return (false, keccak256("SESSION_VALUE"));
		return (true, bytes32(0));
	}

	function _isTimeValid(Session memory session) internal view returns (bool) {
		if (block.timestamp < session.validAfter) return false;
		if (session.validUntil != 0 && block.timestamp > session.validUntil) return false;
		return true;
	}

	function _isScopeValid(
		address account,
		address signer,
		Session memory session,
		Call[] calldata calls
	) internal view returns (bool) {
		for (uint256 i = 0; i < calls.length; i++) {
			if (session.targetAllowlistEnabled && !allowedTarget[account][signer][calls[i].target]) {
				return false;
			}
			if (session.selectorAllowlistEnabled) {
				bytes4 selector = _selector(calls[i].data);
				if (!allowedSelector[account][signer][calls[i].target][selector]) return false;
			}
		}
		return true;
	}

	function _isValueValid(Session memory session, Call[] calldata calls) internal pure returns (bool) {
		if (session.maxValuePerTx == 0) return true;
		for (uint256 i = 0; i < calls.length; i++) {
			if (calls[i].value > session.maxValuePerTx) return false;
		}
		return true;
	}

	function _selector(bytes calldata data) internal pure returns (bytes4) {
		if (data.length < 4) return bytes4(0);
		return bytes4(data[:4]);
	}

	function _scopeHash(
		SessionConfig calldata cfg,
		address[] calldata targets,
		bytes4[][] calldata selectors
	) internal pure returns (bytes32) {
		return keccak256(abi.encode(cfg, targets, selectors));
	}
}
