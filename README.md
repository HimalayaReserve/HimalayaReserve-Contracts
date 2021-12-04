# HimalayaReserve 2.0: MasterChefV2 Security Enhanced

Himalaya Reserve 2.0 is a secret experimental decentralized system governed by decentralized autonomous organization(DAO), while the centralized Himalaya Reserve 1.0 is launched on November 1st, 2021. It has world's first duel coin design including HCN(Himalaya Coin) and HDO(Himalaya Dollar). Every HDO is 1:1 pegged on US Dollar and 100% of its circulalation will be bought back by the Himalaya Reserve Foundation one year after deployment. Every HCN is 1:1,000 hard pegged on HDO during first year and every HCN circulated on Binance Chain worths at least $1,000.

HCN >= $1,000
HDO == $1

### Completely removed the trust of the owner.

### 1.Removed migrator() function

### 2.All configuration functions are 720-hour timelocked

### 3.How to check whether all governance functions are locked or not:
Call TIMELOCK() with fucntion id, eg: "1", to check if "add()" is locked. If the returned value is 0, it is locked. If the returned value is not 0, it would be the timestamp 72 hours after calling the unlock() tx. And when the current timestamp is larger than the returned timestamp, the owner can call the unlocked functions.

// Below is the id list of all governance functions that can be unlocked/locked. By default, all functions are locked and all returned values of the functions available for the owner are 0.

    0: airdropByOwner()
    1: add()
    2: addList()
    3: setToken()
    4: set()
    5: setList()
    6: updateMultiplier()
    7: updateEmissionRate()
    8: upgrade()

 ### How to unlock one specific function:
Owner calls unlock() function with a specific function id, eg: owner unlocks "upgrade()" through calling "unlock()" with "8" as its parameter. And the community can check the lock/unlock status via calling TIMELOCK() with "8" as parameter.

### 4.Restrictions of using unlocked functions:

 require (_allocPoint <= 200 && _depositFeeBP <= 1000, 'add: invalid allocpoints or deposit fee basis points');

### 4.Owner can NOT set deposit fee higher than 10%

a. Every time the owner calls the unlocked function, it would be 720-hour locked again automatically. It means the owner can not regularly change the underlying protocol.
b.Owner can NOT change _allocation point into an infinite number
    // require (_allocPoint <= 200 && _depositFeeBP <= 500, 'add: invalid allocpoints or deposit fee basis points');
c.Owner can NOT set deposit fee higher than 5%
    // uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
    // require (_allocPoint <= 5000 && _depositFeeBP <= 500, 'set: invalid allocpoints or deposit fee basis points');
d.Owner can NOT set multiplier higher than 5
    // require(multiplierNumber <= 5, 'multipler too high');
e.Owner can NOT set emission rate higher than the initial himalaya per block
    // require(_himalayaPerBlock <= 1000000000000000000, 'must be smaller than the initial emission rate');
f.upgrade() function should NOT be unlocked unless it is really necessary to upgrade the protocol. The returned value of calling TIMELOCK() with parameter "8" should ALWAYS be 0.
g.In fact, to achieve maximum security, all returned values for calling TIMELOCK() with parameters from 0 to 8 should be 0, which means all governance functions are perfectly locked.

 uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
 
 require (_allocPoint <= 5000 && _depositFeeBP <= 1000, 'set: invalid allocpoints or deposit fee basis points');

### 6.ReentrancyGuard for deposit(), withdraw(), emergencyWithdraw()

## HCN TOKEN

https://bscscan.com/token/0x631fCFC56733D55b903cCc3fda24360313c90A5B

## HCN-BNB

https://bscscan.com/token/0x69B2A242ec42Aa79098AEEC93a30aFd57b0ECf58

## HCN-USDT

https://bscscan.com/token/0xBcEC44080135AA5B5CD5adc65F15b61D045923a7

## HCN RESERVE

https://bscscan.com/address/0xbeCA582d6fEDd019AdD5C81d41CAd7067a840d4a

## MULTICALL

https://bscscan.com/address/0x1ee38d535d541c55c9dae27b12edf090c608e6fb
