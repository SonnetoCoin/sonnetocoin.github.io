// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Sonneto is ERC20, Ownable, ReentrancyGuard {
    // Constants for maximum supply and initial tokenomics
    uint256 public constant MAX_SUPPLY = 800 * 10**9 * 10**9; // 800 billion tokens with 9 decimals
    uint256 public constant INITIAL_BURN_PERCENTAGE = 30; // 30% to be burned on launch
    uint256 public constant COMMUNITY_AND_MARKETING_WALLET_PERCENTAGE = 20; // 20% to community wallet
    uint256 public constant BURN_FEE = 4; // 4% burned on transactions
    uint256 public constant LIQUIDITY_FEE = 3; // 3% added to liquidity on transactions
    
    // Immutable variables for router and community wallet (set once in constructor)
    address public immutable pancakeSwapRouterAddress;
    IUniswapV2Router02 public immutable pancakeSwapRouter;
    
    // Community and marketing wallet address
    address public communityAndMarketingWallet;

    // Mapping to exclude specific addresses from fees
    mapping(address => bool) private _isExcludedFromFee;

    // Events for key actions
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event FeesExcluded(address indexed account, bool isExcluded);

    /**
     * @dev Constructor to initialize the token with community wallet and router address.
     * @param _communityWallet The address for the community and marketing wallet.
     * @param _routerAddress The address of the PancakeSwap router.
     */
    constructor(address _communityWallet, address _routerAddress) 
        ERC20("Sonneto", "SONNO")
        Ownable(msg.sender)
    {
        require(_communityWallet != address(0), "Community wallet cannot be zero address");
        require(_routerAddress != address(0), "Router address cannot be zero address");

        communityAndMarketingWallet = _communityWallet;
        pancakeSwapRouterAddress = _routerAddress;
        pancakeSwapRouter = IUniswapV2Router02(pancakeSwapRouterAddress);

        uint256 communityAndMarketingAllocation = (MAX_SUPPLY * COMMUNITY_AND_MARKETING_WALLET_PERCENTAGE) / 100;
        uint256 burnAmount = (MAX_SUPPLY * INITIAL_BURN_PERCENTAGE) / 100;
        uint256 initialSupply = MAX_SUPPLY - communityAndMarketingAllocation;

        _mint(msg.sender, initialSupply);
        _mint(communityAndMarketingWallet, communityAndMarketingAllocation);
        _burn(msg.sender, burnAmount);

        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[msg.sender] = true;
    }

    /**
     * @dev Overrides the default `decimals()` function to return 9 decimals.
     */
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /**
     * @dev Transfers tokens with fees applied (burn and liquidity).
     * @param sender The sender address.
     * @param recipient The recipient address.
     * @param amount The amount of tokens to transfer.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        uint256 liquidAmount = amount;

        if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient] && amount>0) {
            uint256 burnAmount = (amount * BURN_FEE) / 100;
            uint256 liquidityAmount = (amount * LIQUIDITY_FEE) / 100;

            super._transfer(sender, address(this), liquidityAmount);
            super._transfer(sender, address(0), burnAmount);

            liquidAmount = amount - burnAmount - liquidityAmount;
        }

        super._transfer(sender, recipient, liquidAmount);
    }

    /**
     * @dev Adds liquidity to the PancakeSwap liquidity pool.
     * @param tokenAmount The amount of tokens to add to liquidity.
     * @param bnbAmount The amount of BNB to add to liquidity.
     */
    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) public onlyOwner {
        _approve(address(this), address(pancakeSwapRouter), tokenAmount);

        pancakeSwapRouter.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );

        emit LiquidityAdded(tokenAmount, bnbAmount);
    }

    /**
     * @dev Excludes or includes an address from transaction fees.
     * @param account The account to be excluded/included.
     * @param excluded True to exclude, false to include.
     */
    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        _isExcludedFromFee[account] = excluded;
        emit FeesExcluded(account, excluded);
    }

    /**
     * @dev Checks if an address is excluded from fees.
     * @param account The address to check.
     * @return True if the address is excluded from fees, otherwise false.
     */
    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    /**
     * @dev Withdraws any BNB balance held by the contract to the owner's address.
     */
    function withdrawBNB() external onlyOwner nonReentrant {
        require(address(this).balance > 0, "No BNB to withdraw");
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {}
}