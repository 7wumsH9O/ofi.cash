interface IOKLend {
    function mint(uint256 _amount) external;
    function redeem(uint256 _amount) external ;
    function balanceOf(address _account) external view returns(uint256);
}