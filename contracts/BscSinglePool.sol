pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./interface/ivenus.sol";
import "./Third.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// MasterChef is the master of RIT. He can make RIT and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once RIT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract BscSinglePool is Third {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IUniswapV2Router02 public router;
    // Info of each uRIT.
    struct URITInfo {
        uint256 amount;     // How many LP tokens the uRIT has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLpDebt; // 已经分的lp利息.
        //
        // We do some fancy math here. Basically, any point in time, the amount of RITs
        // entitled to a uRIT but is pending to be distributed is:
        //
        //   pending reward = (uRIT.amount * pool.accRITPerShare) - uRIT.rewardDebt
        //
        // Whenever a uRIT deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRITPerShare` (and `lastRewardBlock`) gets updated.
        //   2. URIT receives the pending reward sent to his/her address.
        //   3. URIT's `amount` gets updated.
        //   4. URIT's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IVenus kswap;           // Address of LP token contract.
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. RITs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that RITs distribution occurs.
        uint256 accRITPerShare; // Accumulated RITs per share, times 1e12. See below.
        uint256 minAMount;
        uint256 maxAMount;
        IERC20 rewardToken;
        uint256 rewardLpAmount;
        uint256 lpSupply;
        uint256 accLpPerShare; // 利润分配
        uint256 deposit_fee; // 1/10000
        uint256 withdraw_fee; // 1/10000
    }
    uint256 public baseReward = 0;
    // The RIT TOKEN!
    Common public rit;
    // Dev address.
    address public devaddr;
    // Fee address.
    address public feeaddr;
    // RIT tokens created per block.
    uint256 public RITPerBlock;
    // Bonus muliplier for early RIT makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each uRIT that stakes LP tokens.
    mapping (uint256 => mapping (address => URITInfo)) public uRITInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    uint256 public fee = 1; // 1% of profit
    uint256 public feeBase = 100; // 1% of profit

    event Deposit(address indexed uRIT, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed uRIT, uint256 indexed pid, uint256 amount,uint256 rewardLp);
    event ReInvest(uint256 indexed pid);
    event SetDev(address indexed devAddress);
    event SetFee(address indexed feeAddress);
    event SetRITPerBlock(uint256 _RITPerBlock);
    event SetPool(uint256 pid ,address lpaddr,uint256 point,uint256 min,uint256 max);
    constructor(
        Common _rit,
        address _feeaddr,
        address _devaddr,
        uint256 _RITPerBlock,
        IUniswapV2Router02 _router
    ) public {
        rit = _rit;
        devaddr = _devaddr;
        feeaddr = _feeaddr;
        RITPerBlock = _RITPerBlock;
        router = _router;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setBaseReward(uint256 _base) public onlyOwner {
        baseReward = _base;
    }

    function setRITPerBlock(uint256 _RITPerBlock) public onlyOwner {
        RITPerBlock = _RITPerBlock;
        emit SetRITPerBlock(_RITPerBlock);
    }

    function setFeebase(uint256 _feeBase) public onlyOwner {
        feeBase = _feeBase;
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function GetPoolInfo(uint256 id) external view returns (PoolInfo memory) {
        return poolInfo[id];
    }

    function GetURITInfo(uint256 id,address addr) external view returns (URITInfo memory) {
        return uRITInfo[id][addr];
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(IVenus _kswap,uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee,IERC20 _rewardToken) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            kswap: _kswap,
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRITPerShare: 0,
            minAMount:_min,
            maxAMount:_max,
            rewardToken:_rewardToken,
            rewardLpAmount:0,
            lpSupply:0,
            accLpPerShare:0, // 利润分配
            deposit_fee:_deposit_fee,
            withdraw_fee:_withdraw_fee
        }));
        approve(poolInfo[poolInfo.length-1]);
        emit SetPool(poolInfo.length-1 , address(_lpToken), _allocPoint, _min, _max);
    }

    // Update the given pool's RIT allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee,IERC20 _rewardToken) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].minAMount = _min;
        poolInfo[_pid].maxAMount = _max;
        poolInfo[_pid].rewardToken = _rewardToken;
        poolInfo[_pid].deposit_fee = _deposit_fee;
        poolInfo[_pid].withdraw_fee = _withdraw_fee;
        emit SetPool(_pid , address(poolInfo[_pid].lpToken), _allocPoint, _min, _max);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending RITs on frontend.
    function pending(uint256 _pid, address _uRIT) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][_uRIT];
        uint256 accRITPerShare = pool.accRITPerShare;
        uint256 lpSupply = pool.lpSupply;
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 RITReward = multiplier.mul(RITPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRITPerShare = accRITPerShare.add(RITReward.mul(1e12).div(lpSupply));
        }
        return uRIT.amount.mul(accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
    }

    // View function to see pending RITs on frontend.
    function rewardLp(uint256 _pid, address _uRIT) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][_uRIT];
        return uRIT.amount.mul(pool.accLpPerShare).div(1e12).sub(uRIT.rewardLpDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid,0,true);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid,uint256 _amount,bool isAdd) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        pool.lpSupply = isAdd ? pool.lpSupply.add(_amount) : pool.lpSupply.sub(_amount);
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 RITReward = multiplier.mul(RITPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        rit.mint(devaddr, RITReward.div(5)); // 20% Development

        rit.mint(address(this), RITReward); // Liquidity reward
        pool.accRITPerShare = pool.accRITPerShare.add(RITReward.mul(1e12).div(pool.lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // add reward variables of the given pool to be up-to-date.
    function updatePoolProfit(uint256 _pid,uint256 _amount,bool isAdd) public {
        PoolInfo storage pool = poolInfo[_pid];
        
        pool.rewardLpAmount = isAdd ? pool.rewardLpAmount.add(_amount) : pool.rewardLpAmount.sub(_amount);
        if (pool.lpSupply == 0) {
            return;
        }
        _amount = _amount.mul(9999).div(10000);
        pool.accLpPerShare = pool.accLpPerShare.add(_amount.mul(1e12).div(pool.lpSupply));
    }

    function testdeposit(uint256 _pid, uint256 _amount) public onlyOwner{
        PoolInfo storage pool = poolInfo[_pid];
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 allowAmount = pool.lpToken.allowance(address(this),address(pool.kswap));
        if (allowAmount<_amount){
            pool.lpToken.approve(address(pool.kswap), uint256(-1));
        }
        pool.kswap.mint(_amount);
    }

    function approve(PoolInfo memory pool) private {
        pool.rewardToken.approve(address(router),uint256(-1));
        pool.rewardToken.approve(address(pool.kswap),uint256(-1));
        pool.lpToken.approve(address(pool.kswap), uint256(-1));
    }

    // Deposit LP tokens to MasterChef for RIT allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][msg.sender];
        
        updatePool(_pid, 0, true); 
        harvest(_pid);// 复投
        uint256 pendingT = uRIT.amount.mul(pool.accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
        if(pendingT > 0) {
            safeRITTransfer(msg.sender, pendingT);
        }
        if(_amount > 0) { // 
            // 先将金额抵押到合约
            if(pool.deposit_fee > 0){
                uint256 feeR = _amount.mul(pool.deposit_fee).div(10000);
                pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, feeR);
                _amount = _amount.sub(feeR);
            }
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            pool.kswap.mint(_amount);
            uRIT.amount = uRIT.amount.add(_amount);

            if (pool.minAMount > 0 && uRIT.amount < pool.minAMount){
                revert("amount is too low");
            }
            if (pool.maxAMount > 0 && uRIT.amount > pool.maxAMount){
                revert("amount is too high");
            }
            pool.lpSupply = pool.lpSupply.add(_amount);
            pool.rewardLpAmount = pool.rewardLpAmount.add(0);
        }
        uRIT.rewardLpDebt = uRIT.rewardLpDebt.add(_amount.mul(pool.accLpPerShare).div(1e12));
        uRIT.rewardDebt = uRIT.amount.mul(pool.accRITPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function testwithdraw(uint256 _pid) public onlyOwner{
        PoolInfo storage pool = poolInfo[_pid];
        pool.kswap.redeem(pool.kswap.balanceOf(address(this)));
        pool.lpToken.safeTransfer(address(msg.sender), pool.lpToken.balanceOf(address(this)));
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][msg.sender];
        require(uRIT.amount >= _amount, "withdraw: not good");
        updatePool(_pid, 0, false);
        uint256 pendingT = uRIT.amount.mul(pool.accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
        if(pendingT > 0) {
            safeRITTransfer(msg.sender, pendingT);
        }
        if(_amount > 0) {
            // 算出总金额
            // 利息复投计算
            // pool.kswap.claim(); // 提出利息
            uint256 fene = pool.kswap.balanceOf(address(this));
            calcProfit(_pid,pool,fene); // 计算利息
            uint256 rewardLp = uRIT.amount.mul(pool.accLpPerShare).div(1e12).sub(uRIT.rewardLpDebt);
            uRIT.amount = uRIT.amount.sub(_amount);
            if(pool.withdraw_fee>0){
                uint256 fee = _amount.mul(pool.withdraw_fee).div(10000);      
                _amount = _amount.sub(fee);
                pool.lpToken.safeTransfer(devaddr, fee);
            }
            // 利息+要退出的本金一起退出
            uint256 withdraw_amount = _amount.add(rewardLp);

            safeLpTransfer(pool,address(msg.sender), withdraw_amount,_amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            futou(pool); //剩余复投
            pool.rewardLpAmount = pool.lpSupply > 0 ? pool.rewardLpAmount.sub(rewardLp) : 0;
            uRIT.rewardLpDebt = uRIT.amount.mul(pool.accLpPerShare).div(1e12);
        } else{
            updatePoolProfit(_pid, 0, false);
        }
        uRIT.rewardDebt = uRIT.amount.mul(pool.accRITPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount,pool.rewardLpAmount);
    }

    function safeLpTransfer(PoolInfo memory pool,address _to, uint256 _amount,uint256 _min) internal {
        uint256 RITBal = pool.lpToken.balanceOf(address(this));
        require(RITBal>=_amount,"wait other platform!!!");
        if (_amount > RITBal) {
            pool.lpToken.transfer(_to, RITBal);
        } else {
            pool.lpToken.transfer(_to, _amount);
        }
    }

    // 计算利息
    function calcProfit(uint256 pid,PoolInfo memory pool,uint256 fene) private{
        // 计算总的利息
        pool.kswap.redeem(fene);
        uint256 ba = pool.rewardToken.balanceOf(address(this));
      
        if(ba > 0){
            // pool.rewardToken.transfer(devaddr,ba);
            uint256 profitFee = ba.mul(fee).div(feeBase);
            pool.rewardToken.safeTransfer(feeaddr,profitFee);
            ba = ba.sub(profitFee);
            address[] memory path = new address[](2);
            path[0] = address(pool.rewardToken); 
            path[1] = address(pool.lpToken);
            router.swapExactTokensForTokens(ba, uint256(0), path, address(this), block.timestamp.add(1800));
        }
        uint256 allBalance = pool.lpToken.balanceOf(address(this));
        if( allBalance > pool.lpSupply.add(pool.rewardLpAmount)){ // 计算出增量的 利息
            updatePoolProfit(pid, allBalance.sub(pool.lpSupply).sub(pool.rewardLpAmount), true);
        }
    }

    function futou(PoolInfo memory pool) private {
        uint256 ba = pool.lpToken.balanceOf(address(this));
        if(ba<=0){
            return;
        }
        if(pool.lpSupply<=0){
            // 如果当前池子质押总额为0 那么多余的反给平台
            pool.lpToken.transfer(feeaddr,ba);
            return;
        }
        // LP利息复投
        pool.kswap.mint(ba);
    }

    // auto reinvest
    function harvest(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 fene = pool.kswap.balanceOf(address(this));
        calcProfit(_pid, pool,fene); // 计算利息 
        futou(pool); // 并复投
        emit ReInvest(_pid);
    }

    // Safe RIT transfer function, just in case if rounding error causes pool to not have enough RITs.
    function safeRITTransfer(address _to, uint256 _amount) internal {
        uint256 RITBal = rit.balanceOf(address(this));
        if (_amount > RITBal) {
            rit.transfer(_to, RITBal);
        } else {
            rit.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "_devaddr is address(0)");
        devaddr = _devaddr;
        emit SetDev(_devaddr);
    }

    // Update fee address by the previous dev.
    function setFee(address _feeaddr) public {
        require(msg.sender == feeaddr, "fee: wut?");
        require(_feeaddr != address(0), "_feeaddr is address(0)");
        feeaddr = _feeaddr;
        emit SetFee(_feeaddr);
    }
}
