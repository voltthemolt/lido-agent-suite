# Security Considerations

## AgentTreasury Smart Contract

**Document Version:** 1.0  
**Last Updated:** March 2026  
**Contract:** `contracts/src/AgentTreasury.sol`

---

## 1. Threat Model

### 1.1 Attackers and Motivations

| Threat Actor | Motivation | Capability |
|--------------|------------|------------|
| **Malicious Agents** | Drain principal, inflate yield, bypass spending limits | Can call public functions, control own treasury |
| **Compromised Service Providers** | Extract excess funds, double-charge | Listed on allowlist, receive payments |
| **MEV Searchers** | Front-run deposits/withdrawals for profit | On-chain monitoring, transaction reordering |
| **Flash Loan Attackers** | Manipulate yield calculations, exploit pricing | Access to large capital instantaneously |
| **Compromised Owner Key** | Full contract takeover, allowlist manipulation | Admin function access |
| **Economic Attackers** | Exploit stETH/wstETH mechanics | Understanding of rebasing and share prices |

### 1.2 Attack Surfaces

1. **Yield Calculation Logic** - Potential for manipulation via flash loans
2. **Allowlist Bypass** - Social engineering or compromised keys
3. **Time-Lock Circumvention** - Race conditions in withdrawal flow
4. **Token Integration Points** - stETH, wstETH interface assumptions
5. **Ownership Functions** - Centralization risks

---

## 2. Smart Contract Risks

### 2.1 Reentrancy Attacks

**Risk Level:** LOW (Mitigated)

**Description:**  
Reentrancy occurs when an external call is made before state updates complete, allowing an attacker to recursively call back into the contract.

**Mitigation in Place:**
```solidity
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgentTreasury is Ownable, ReentrancyGuard, AgentTreasuryEvents {
    // All state-changing functions use nonReentrant modifier
    function deposit(...) external nonReentrant { ... }
    function spendYield(...) external nonReentrant { ... }
    function initiateWithdrawal(...) external nonReentrant { ... }
    function completeWithdrawal() external nonReentrant { ... }
}
```

**Residual Risk:**
- OpenZeppelin's ReentrancyGuard prevents standard reentrancy
- All external calls (transfers, wraps/unwraps) occur after state updates where possible
- Consider using `ReentrancyGuardUpgradeable` if upgrading to UUPS pattern

**Recommendation:**  
The current implementation is sufficient. Ensure any future additions maintain the `nonReentrant` modifier on all functions making external calls.

---

### 2.2 Flash Loan Attacks on Yield Calculation

**Risk Level:** HIGH (Requires Attention)

**Description:**  
Flash loans allow borrowing massive amounts without collateral within a single transaction. An attacker could:

1. Borrow large amount of stETH
2. Deposit to inflate `totalPrincipal`
3. Manipulate share calculations
4. Withdraw with profit
5. Repay flash loan

**Vulnerable Code Section:**
```solidity
function getAvailableYield(address agent) public view returns (uint256) {
    // Current wstETH balance attributed to this agent
    uint256 currentBalance = wstETH.balanceOf(address(this)) * treasury.principalShares / totalPrincipal;
    // ...
}
```

**Attack Vectors:**
1. **Yield Pool Dilution:** Large flash deposit dilutes yield share of legitimate agents
2. **Share Price Manipulation:** Rapid deposit/withdrawal could exploit rounding
3. **First Deposit Attack:** If `totalPrincipal` is 0, division could revert or be exploitable

**Current Mitigations:**
- `MIN_DEPOSIT = 0.01 ether` prevents dust attacks
- wstETH share price is determined by Lido protocol (not manipulable via this contract)
- Yield is calculated per-agent based on their share percentage

**Residual Risks:**
- No TWAP (Time-Weighted Average Price) for yield calculation
- Single-block manipulation possible
- No minimum holding period before yield can be spent

**Recommendations:**
1. Consider adding a minimum holding period (e.g., 24 hours) before yield becomes spendable
2. Implement a rolling average for yield calculation instead of spot price
3. Add a maximum single-spend percentage (e.g., max 50% of available yield per transaction)
4. Consider snapshot-based yield distribution

---

### 2.3 Principal Theft Vectors

**Risk Level:** MEDIUM

**Description:**  
Various mechanisms could allow attackers to access principal they don't own.

**Analyzed Vectors:**

**a) Withdrawal Race Condition**
```solidity
function initiateWithdrawal(uint256 amount) external nonReentrant hasTreasury {
    // ...
    require(!pendingWithdrawals[msg.sender].exists, "Withdrawal already pending");
    // ...
}

function completeWithdrawal() external nonReentrant hasTreasury {
    // ...
    treasury.principalShares -= sharesToWithdraw;
    totalPrincipal -= sharesToWithdraw;
    // ...
}
```

**Mitigation:** 7-day time-lock (`WITHDRAWAL_LOCK = 7 days`) provides security window. Cannot have multiple pending withdrawals.

**b) Integer Overflow/Underflow**
- Solidity ^0.8.20 provides built-in overflow protection
- All arithmetic operations revert on overflow

**c) Share Calculation Manipulation**
```solidity
uint256 currentBalance = wstETH.balanceOf(address(this)) * treasury.principalShares / totalPrincipal;
```
- Multiplication before division maintains precision
- Risk of truncation loss for small holders (acceptable, not exploitable)

**d) Cross-Agent Principal Confusion**
- Each agent has isolated `AgentTreasuryInfo`
- `totalPrincipal` correctly tracks aggregate
- Withdrawal properly decrements both individual and total

**Residual Risks:**
- No emergency pause mechanism
- If owner key is compromised, allowlist can be manipulated to drain yield
- No rate limiting on withdrawals

**Recommendations:**
1. Add emergency pause functionality via Pausable pattern
2. Implement withdrawal rate limiting (e.g., max 50% per withdrawal)
3. Add multi-sig requirement for owner functions

---

### 2.4 Allowlist Bypass

**Risk Level:** MEDIUM-HIGH

**Description:**  
The allowlist controls who can receive yield payments. Bypass could enable unauthorized payments.

**Allowlist Implementation:**
```solidity
mapping(address => bool) public spendingAllowlist;

modifier onlyAllowlisted(address recipient) {
    require(spendingAllowlist[recipient], "Recipient not allowlisted");
    _;
}

function allowlistSpending(address recipient, string calldata service) external onlyOwner {
    spendingAllowlist[recipient] = true;
    emit SpendingAllowlisted(recipient, service);
}
```

**Attack Vectors:**

1. **Compromised Owner Key**
   - Attacker with owner key can add arbitrary addresses to allowlist
   - Can then drain all yield through malicious "service providers"

2. **Front-Running Allowlist Addition**
   - Attacker sees pending allowlist transaction
   - Can prepare spend transaction to front-run legitimate use

3. **Malicious Service Provider**
   - Legitimate service turns malicious after being allowlisted
   - Social engineering to get allowlisted

4. **Address Spoofing**
   - Attacker creates address similar to legitimate service
   - Tricks owner into allowlisting wrong address

**Current Mitigations:**
- Events emitted for transparency (`SpendingAllowlisted`, `SpendingDelisted`)
- Off-chain monitoring possible

**Missing Mitigations:**
- No delay between allowlisting and first spend
- No spending limits per allowlisted address
- No multi-sig for allowlist management
- No timelock on allowlist changes

**Recommendations:**
1. Implement a 48-hour delay before new allowlist entries become active
2. Add per-recipient spending limits (daily/monthly caps)
3. Use multi-sig for owner functions
4. Implement a delisting delay (immediate delisting on detection is good)
5. Add service provider verification requirements before allowlisting

---

## 3. Economic Risks

### 3.1 stETH Rebasing Mechanics

**Risk Level:** MEDIUM

**Description:**  
stETH uses a rebasing mechanism where balances increase daily as staking rewards accrue. This creates unique risks.

**Key Mechanics:**
- stETH balance increases ~4-5% annually
- wstETH (wrapped stETH) maintains constant balance, increasing in value instead
- Conversion rate: `wstETH_amount * wstETH_to_stETH_rate = stETH_amount`

**Risks:**

1. **Negative Rebases (Slashing)**
   - If Lido validators are slashed, stETH balance could decrease
   - Principal value would drop below deposited amount
   - Contract assumes principal can only grow

2. **Rebase Timing Arbitrage**
   - stETH rebases occur at specific times
   - Attacker could deposit just before rebase, withdraw just after
   - Would capture yield without time exposure

3. **Lido Withdrawal Queue Delays**
   - Unwrapping wstETH returns stETH, not ETH
   - Converting stETH to ETH requires Lido withdrawal queue
   - Queue can have multi-day delays during high activity

**Contract Code Analysis:**
```solidity
function deposit(uint256 amount, uint256 erc8004Id) external nonReentrant {
    // ...
    uint256 wstETHAmount = wstETH.wrap(amount);
    treasury.principalShares = wstETHAmount;
    // ...
}
```

**Issue:** Principal is recorded in wstETH shares, which maintains value through rebases. This is correct.

**Residual Risks:**
- Negative rebase could reduce principal value
- No minimum yield guarantee
- Dependency on Lido protocol security

**Recommendations:**
1. Add documentation about negative rebase risk
2. Consider a principal protection buffer (e.g., reserve 5% for negative rebases)
3. Monitor Lido slashing events and have emergency response plan

---

### 3.2 wstETH Share Price Manipulation

**Risk Level:** LOW

**Description:**  
wstETH share price is determined by the Lido protocol, not by this contract's activity.

**Why This Is Low Risk:**
- wstETH share price is set by Lido's total pooled ETH / total shares
- Single contract's deposits cannot meaningfully manipulate this
- Lido TVL is too large for manipulation

**Residual Consideration:**
- If Lido itself is compromised, all wstETH could be affected
- This is a protocol-level risk, not contract-specific

---

### 3.3 MEV Extraction on Swaps

**Risk Level:** MEDIUM

**Description:**  
MEV (Maximal Extractable Value) can be extracted through transaction ordering.

**MEV Vectors:**

1. **Front-Running Deposits**
   - Attacker sees large pending deposit
   - Front-runs to deposit before, captures yield share
   - Back-runs to withdraw after

2. **Sandwich Attacks on Yield Spend**
   - Attacker sandwiches yield spend transactions
   - Manipulates perceived yield availability

3. **Withdrawal Frontrunning**
   - Attacker sees withdrawal completion pending
   - Could manipulate share price timing

**Mitigating Factors:**
- Yield accumulates over time (not instantly extractable)
- 7-day time-lock on withdrawals limits MEV
- No DEX integration (no direct swap manipulation)

**Residual Risks:**
- Block builders could reorder transactions
- Private mempool needed for large transactions

**Recommendations:**
1. Use Flashbots Protect RPC for large deposits/withdrawals
2. Consider implementing a commit-reveal scheme for sensitive operations
3. Add slippage protection for any future swap integrations

---

## 4. Operational Risks

### 4.1 Owner Key Management

**Risk Level:** HIGH

**Description:**  
The contract uses OpenZeppelin's `Ownable` pattern with a single owner having full control.

**Owner Powers:**
- Add/remove addresses from spending allowlist
- Transfer ownership to new address
- No timelock on these actions

**Code Reference:**
```solidity
contract AgentTreasury is Ownable, ReentrancyGuard, AgentTreasuryEvents {
    // ...
    function allowlistSpending(address recipient, string calldata service) external onlyOwner {
        spendingAllowlist[recipient] = true;
        emit SpendingAllowlisted(recipient, service);
    }
    
    function delistSpending(address recipient) external onlyOwner {
        spendingAllowlist[recipient] = false;
        emit SpendingDelisted(recipient);
    }
}
```

**Risk Scenarios:**
1. Owner private key stolen → complete control of allowlist
2. Owner acts maliciously → add attacker addresses to allowlist
3. Owner key lost → cannot update allowlist, system frozen

**Recommendations:**

1. **Immediate (Pre-Deployment):**
   - Use hardware wallet for owner key
   - Document key custody procedures

2. **Short-Term:**
   - Migrate to `Ownable2Step` for safer ownership transfers
   - Add timelock to owner functions

3. **Long-Term:**
   - Implement multi-sig (Gnosis Safe) for ownership
   - Consider DAO governance for allowlist management

---

### 4.2 Service Provider Vetting

**Risk Level:** MEDIUM

**Description:**  
Allowlisted service providers can receive payments without further verification.

**Current Process (Implicit):**
- Owner decides which addresses to allowlist
- No formal vetting requirements documented
- No ongoing monitoring requirements

**Risks:**
1. Insufficient vetting allows malicious providers
2. Providers can change behavior after being added
3. No verification that provider address matches claimed identity
4. No revocation process for compromised providers

**Recommendations:**

1. **Vetting Requirements:**
   - KYB (Know Your Business) for service providers
   - Smart contract audit for on-chain services
   - Insurance coverage for large providers
   - Documented service-level agreements

2. **Ongoing Monitoring:**
   - Daily spend limits per provider
   - Anomaly detection for unusual patterns
   - Regular re-verification (quarterly)

3. **Revocation Process:**
   - Document incident response procedures
   - Immediate delisting capability (exists)
   - Communication plan for affected agents

---

### 4.3 Upgrade Path

**Risk Level:** MEDIUM

**Description:**  
The current contract is immutable with no upgrade mechanism.

**Implications:**
- Bugs cannot be patched
- Features cannot be added
- Integration changes require new contract deployment
- Migration would require all agents to withdraw and re-deposit

**Current State:**
```solidity
contract AgentTreasury is Ownable, ReentrancyGuard, AgentTreasuryEvents {
    // No upgradeability pattern implemented
    // Immutable once deployed
}
```

**Trade-offs:**
| Immutable | Upgradeable |
|-----------|-------------|
| Trustless | Requires trust in upgrade key |
| No rug pull risk | Can fix bugs |
| Simple audit | Complex proxy patterns |

**Recommendations:**

1. **For Current Deployment:**
   - Thoroughly audit before deployment
   - Consider bug bounty program
   - Document migration path for future

2. **For Future Version:**
   - Consider UUPS upgradeable pattern
   - Time-locked upgrades (e.g., 7-day delay)
   - Multi-sig controlled upgrades

3. **Migration Considerations:**
   - Design upgrade with agent consent
   - Each agent must explicitly migrate
   - Do not force migration on existing users

---

## 5. Audit Recommendations

### 5.1 Required Audits

| Audit Type | Priority | Timeline | Scope |
|------------|----------|----------|-------|
| Smart Contract Audit | Critical | Pre-launch | Full contract + tests |
| Economic Model Review | High | Pre-launch | Yield calculations, edge cases |
| Integration Audit | Medium | Post-launch | stETH/wstETH interactions |
| Operational Audit | Medium | Pre-launch | Owner procedures, access controls |

### 5.2 Recommended Auditors

1. **Primary Audit:** Trail of Bits, OpenZeppelin, or Spearbit
2. **Economic Review:** Gauntlet or Chaos Labs
3. **Formal Verification:** Certora (for yield calculation logic)

### 5.3 Audit Scope Items

- [ ] All public/external functions
- [ ] View functions for correct return values
- [ ] Modifier interactions
- [ ] Token integration assumptions
- [ ] Edge cases (zero values, max values)
- [ ] Multi-agent scenarios
- [ ] Withdrawal flow with time-lock
- [ ] Allowlist management
- [ ] Event emission completeness

### 5.4 Pre-Audit Checklist

- [ ] Achieve 100% test coverage on core functions
- [ ] Run Slither static analysis
- [ ] Run Echidna fuzzing tests
- [ ] Complete internal code review
- [ ] Document all assumptions in natspec
- [ ] Create comprehensive test scenarios

### 5.5 Post-Audit Actions

- [ ] Address all critical findings before deployment
- [ ] Document high/medium findings with rationale
- [ ] Create remediation plan for low findings
- [ ] Schedule follow-up audit if significant changes made

---

## 6. Known Limitations and Assumptions

### 6.1 Technical Limitations

1. **Single Chain Operation**
   - Contract operates on single chain only
   - No cross-chain yield aggregation
   - wstETH must be canonical L2 version if deployed elsewhere

2. **No Yield Guarantee**
   - Yield depends on Lido staking rewards
   - Negative rebases can reduce effective principal
   - No minimum APY guaranteed

3. **Withdrawal Dependencies**
   - Unwrapping wstETH returns stETH, not ETH
   - StETH to ETH conversion subject to Lido withdrawal queue
   - Queue can have multi-day delays

4. **Gas Costs**
   - Multiple operations per transaction (wrap/unwrap)
   - Not optimized for L2 deployment currently
   - High gas may make small deposits uneconomical

### 6.2 Economic Assumptions

1. **Lido Protocol Security**
   - Assumes Lido operates securely
   - Assumes stETH maintains peg to ETH
   - Assumes no catastrophic slashing events

2. **Market Conditions**
   - Assumes stETH liquidity remains available
   - Assumes reasonable stETH/ETH exchange rate stability
   - No protection against market manipulation

3. **Yield Calculation**
   - Assumes linear yield distribution is acceptable
   - No compounding within contract (handled by wstETH)
   - Rounding errors accepted for small amounts

### 6.3 Operational Assumptions

1. **Owner Competence**
   - Assumes owner key holder acts honestly
   - Assumes proper vetting of service providers
   - Assumes timely response to incidents

2. **Service Provider Behavior**
   - Assumes allowlisted providers are legitimate
   - Assumes providers will deliver services as promised
   - No on-chain verification of service delivery

3. **Agent Behavior**
   - Assumes agents will monitor their treasuries
   - Assumes agents understand withdrawal delays
   - No protection against agent private key loss

### 6.4 Out of Scope

The following are explicitly **NOT** addressed by this contract:

- Agent identity verification beyond ERC-8004 optional field
- Dispute resolution between agents and service providers
- Recovery of lost agent private keys
- Insurance against slashing or negative rebases
- Compliance with local regulations (tax, KYC, etc.)
- Cross-chain operations or bridging

---

## 7. Security Checklist

### Pre-Deployment

- [ ] Complete smart contract audit
- [ ] Address all critical/high findings
- [ ] Set up owner key on hardware wallet
- [ ] Document owner key custody procedure
- [ ] Establish service provider vetting process
- [ ] Set up monitoring and alerting
- [ ] Create incident response plan
- [ ] Test deployment on testnet
- [ ] Verify correct wstETH/stETH addresses
- [ ] Set up block explorer verification

### Post-Deployment

- [ ] Verify contract deployment
- [ ] Test deposit/withdrawal flow
- [ ] Add initial service providers to allowlist
- [ ] Set up event monitoring
- [ ] Establish regular security reviews
- [ ] Create user documentation
- [ ] Launch bug bounty program

---

## 8. Incident Response

### 8.1 Contact Information

| Role | Contact | Escalation |
|------|---------|------------|
| Security Lead | [TBD] | Primary responder |
| Owner Key Holder | [TBD] | Emergency actions |
| Legal Counsel | [TBD] | Regulatory issues |

### 8.2 Response Procedures

1. **Detection:** Monitor events for unusual activity
2. **Assessment:** Classify severity (Critical/High/Medium/Low)
3. **Containment:** Delist malicious addresses if needed
4. **Eradication:** Identify and fix root cause
5. **Recovery:** Restore normal operations
6. **Post-Mortem:** Document and improve

### 8.3 Emergency Contacts

- Lido Security: security@lido.fi
- Ethereum Foundation: bounty@ethereum.org

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | March 2026 | Initial security document |

---

*This document should be reviewed and updated with each contract modification or significant operational change.*
