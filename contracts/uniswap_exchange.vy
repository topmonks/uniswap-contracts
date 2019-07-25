# @title Uniswap Exchange Interface V2
# @notice Source code found at https://github.com/uniswap
# @notice Use at your own risk

contract Factory():
    def getExchange(base_addr: address, token_a: address) -> address: constant

contract Token():
    def balanceOf(_owner: address) -> uint256: constant
    def transfer(_to: address, _value: uint256) -> bool: modifying
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: modifying


SwapAForB: event({buyer: indexed(address), amount_sold: indexed(uint256), amount_bought: indexed(uint256)})
SwapBForA: event({buyer: indexed(address), amount_sold: indexed(uint256), amount_bought: indexed(uint256)})
AddLiquidity: event({provider: indexed(address), base_amount: indexed(uint256), token_amount: indexed(uint256)})
RemoveLiquidity: event({provider: indexed(address), base_amount: indexed(uint256), token_amount: indexed(uint256)})
Transfer: event({_from: indexed(address), _to: indexed(address), _value: uint256})
Approval: event({_owner: indexed(address), _spender: indexed(address), _value: uint256})

name: public(string[32])                                    # Uniswap V1
symbol: public(string[32])                                  # UNI-V1
decimals: public(uint256)                                   # 18
totalSupply: public(uint256)                                # total number of UNI in existence
balanceOf: public(map(address, uint256))                    # UNI balance of an address
allowance: public(map(address, map(address, uint256)))      # UNI allowance of one address on another
tokenA: public(Token)                                       # address of the ERC20 token traded on this contract
tokenB: public(Token)                                       # address of the ERC20 token traded on this contract
factory: public(Factory)                                    # interface for the factory that created this contract



# @dev This function acts as a contract constructor which is not currently supported in contracts deployed
#      using create_with_code_of(). It is called once by the factory during contract creation.
@public
def setup(token_a: address, token_b: address):
    assert (self.factory == ZERO_ADDRESS and self.tokenA == ZERO_ADDRESS) and self.tokenB == ZERO_ADDRESS
    assert token_a != ZERO_ADDRESS and token_b != ZERO_ADDRESS
    self.factory = Factory(msg.sender)
    self.tokenA = Token(token_a)
    self.tokenB = Token(token_b)
    self.name = 'Uniswap V2'
    self.symbol = 'UNI-V2'
    self.decimals = 18

# @return Address of factory that created this exchange.
@public
@constant
def factoryAddress() -> address(Factory):
    return self.factory

# @notice Deposit ETH and Tokens (self.token) at current ratio to mint UNI tokens.
# @dev min_liquidity does nothing when total UNI supply is 0.
# @param min_liquidity Minimum number of UNI sender will mint if total UNI supply is greater than 0.
# @param max_tokens Maximum number of tokens deposited. Deposits max amount if total UNI supply is 0.
# @param deadline Time after which this transaction can no longer be executed.
# @return The amount of UNI minted.
@public
def addLiquidity(tokenA_amount: uint256, max_tokenB: uint256, min_liquidity: uint256, deadline: timestamp) -> uint256:
    assert deadline >= block.timestamp and (max_tokenB > 0 and tokenA_amount > 0)
    total_liquidity: uint256 = self.totalSupply
    if total_liquidity > 0:
        assert min_liquidity > 0
        tokenA_reserve: uint256 = self.tokenA.balanceOf(self)
        tokenB_reserve: uint256 = self.tokenB.balanceOf(self)
        tokenB_amount: uint256 = tokenA_amount * tokenA_reserve / tokenB_reserve + 1
        liquidity_minted: uint256 = tokenA_amount * total_liquidity / tokenB_reserve
        assert max_tokenB >= tokenB_amount and liquidity_minted >= min_liquidity
        self.balanceOf[msg.sender] += liquidity_minted
        self.totalSupply = total_liquidity + liquidity_minted
        successBase: bool = self.tokenB.transferFrom(msg.sender, self, tokenA_amount)
        successToken: bool = self.tokenA.transferFrom(msg.sender, self, tokenB_amount)
        assert successBase and successToken
        log.AddLiquidity(msg.sender, tokenA_amount, tokenB_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, liquidity_minted)
        return liquidity_minted
    else:
        # TODO: assert msg.value >= 1000000000 equivalent
        assert self.factory != ZERO_ADDRESS and self.tokenA != ZERO_ADDRESS
        assert self.factory.getExchange(self.tokenB, self.tokenA) == self
        tokenB_amount: uint256 = max_tokenB
        initial_liquidity: uint256 = as_unitless_number(self.balance)
        self.totalSupply = initial_liquidity
        self.balanceOf[msg.sender] = initial_liquidity
        transferTokenA: bool = self.tokenA.transferFrom(msg.sender, self, tokenA_amount)
        transferTokenB: bool = self.tokenB.transferFrom(msg.sender, self, tokenB_amount)
        assert transferTokenA and transferTokenB
        log.AddLiquidity(msg.sender, tokenA_amount, tokenB_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, initial_liquidity)
        return initial_liquidity

# @dev Burn UNI tokens to withdraw ETH and Tokens at current ratio.
# @param amount Amount of UNI burned.
# @param min_eth Minimum ETH withdrawn.
# @param min_tokens Minimum Tokens withdrawn.
# @param deadline Time after which this transaction can no longer be executed.
# @return The amount of ETH and Tokens withdrawn.
@public
def removeLiquidity(amount: uint256, min_base: uint256, min_tokens: uint256, deadline: timestamp) -> (uint256, uint256):
    assert (amount > 0 and deadline >= block.timestamp) and (min_base > 0 and min_tokens > 0)
    total_liquidity: uint256 = self.totalSupply
    assert total_liquidity > 0
    base_reserve: uint256 = self.tokenB.balanceOf(self)
    token_reserve: uint256 = self.tokenA.balanceOf(self)
    base_amount: uint256 = amount * base_reserve / total_liquidity
    token_amount: uint256 = amount * token_reserve / total_liquidity
    assert base_amount >= min_base and token_amount >= min_tokens
    self.balanceOf[msg.sender] -= amount
    self.totalSupply = total_liquidity - amount
    baseTransfer: bool = self.tokenB.transfer(msg.sender, token_amount)
    tokenTransfer: bool = self.tokenA.transfer(msg.sender, token_amount)
    assert baseTransfer and tokenTransfer
    log.RemoveLiquidity(msg.sender, base_amount, token_amount)
    log.Transfer(msg.sender, ZERO_ADDRESS, amount)
    return base_amount, token_amount

# @dev Pricing function for converting between ETH and Tokens.
# @param input_amount Amount of ETH or Tokens being sold.
# @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves.
# @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves.
# @return Amount of ETH or Tokens bought.
@private
@constant
def getInputPrice(input_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    assert input_reserve > 0 and output_reserve > 0
    input_amount_with_fee: uint256 = input_amount * 997
    numerator: uint256 = input_amount_with_fee * output_reserve
    denominator: uint256 = (input_reserve * 1000) + input_amount_with_fee
    return numerator / denominator

# @dev Pricing function for converting between ETH and Tokens.
# @param output_amount Amount of ETH or Tokens being bought.
# @param input_reserve Amount of ETH or Tokens (input type) in exchange reserves.
# @param output_reserve Amount of ETH or Tokens (output type) in exchange reserves.
# @return Amount of ETH or Tokens sold.
@private
@constant
def getOutputPrice(output_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    assert input_reserve > 0 and output_reserve > 0
    numerator: uint256 = input_reserve * output_amount * 1000
    denominator: uint256 = (output_reserve - output_amount) * 997
    return numerator / denominator + 1

@public
def swapInput(input_token: address, amount_sold: uint256, min_bought: uint256, recipient: address) -> uint256:

    token_a: address = self.tokenA
    token_b: address = self.tokenB
    input_a: bool = input_token == token_a
    input_b: bool = input_token == token_b
    assert (input_a or input_b), 'Invalid input token'

    output_token: address = ZERO_ADDRESS
    if input_a:
        output_token = token_b
    else:
        output_token = token_a

    input_reserve: uint256 = Token(input_token).balanceOf(self)
    output_reserve: uint256 = Token(output_token).balanceOf(self)
    amount_bought: uint256 = self.getInputPrice(amount_sold, input_reserve, output_reserve)

    transferInput: bool = Token(input_token).transferFrom(msg.sender, self, amount_sold)
    transferOutput: bool = Token(output_token).transfer(recipient, amount_bought)
    assert transferInput and transferOutput

    if input_a:
        log.SwapAForB(msg.sender, amount_sold, amount_bought)
    else:
        log.SwapBForA(msg.sender, amount_sold, amount_bought)

    return amount_bought

# # @notice Public price function for ETH to Token trades with an exact input.
# # @param eth_sold Amount of ETH sold.
# # @return Amount of Tokens that can be bought with input ETH.
# @public
# @constant
# def getBaseToTokenInputPrice(base_sold: uint256) -> uint256:
#     assert base_sold > 0
#     base_reserve: uint256 = self.tokenB.balanceOf(self)
#     token_reserve: uint256 = self.tokenA.balanceOf(self)
#     tokens_bought: uint256 = self.getInputPrice(base_sold, base_reserve, token_reserve)
#     return tokens_bought
#
# # @notice Public price function for ETH to Token trades with an exact output.
# # @param tokens_bought Amount of Tokens bought.
# # @return Amount of ETH needed to buy output Tokens.
# @public
# @constant
# def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256:
#     assert tokens_bought > 0
#     base_reserve: uint256 = self.tokenB.balanceOf(self)
#     token_reserve: uint256 = self.tokenA.balanceOf(self)
#     base_sold: uint256 = self.getOutputPrice(tokens_bought, base_reserve, token_reserve)
#     return base_sold
#
# # @notice Public price function for Token to ETH trades with an exact input.
# # @param tokens_sold Amount of Tokens sold.
# # @return Amount of ETH that can be bought with input Tokens.
# @public
# @constant
# def getTokenToBaseInputPrice(tokens_sold: uint256) -> uint256:
#     assert tokens_sold > 0
#     base_reserve: uint256 = self.tokenB.balanceOf(self)
#     token_reserve: uint256 = self.tokenA.balanceOf(self)
#     base_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, base_reserve)
#     return base_bought
#
# # @notice Public price function for Token to ETH trades with an exact output.
# # @param eth_bought Amount of output ETH.
# # @return Amount of Tokens needed to buy output ETH.
# @public
# @constant
# def getTokenToEthOutputPrice(base_bought: uint256) -> uint256:
#     assert base_bought > 0
#     base_reserve: uint256 = self.tokenB.balanceOf(self)
#     token_reserve: uint256 = self.tokenA.balanceOf(self)
#     tokens_sold: uint256 = self.getOutputPrice(base_bought, token_reserve, base_reserve)
#     return tokens_sold

# ERC20 compatibility for exchange liquidity modified from
# https://github.com/ethereum/vyper/blob/master/examples/tokens/ERC20.vy
@public
def transfer(_to: address, _value: uint256) -> bool:
    assert _value > 0
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log.Transfer(msg.sender, _to, _value)
    return True

@public
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _value > 0
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    if _value < MAX_UINT256:
        self.allowance[_from][msg.sender] -= _value
    log.Transfer(_from, _to, _value)
    return True

@public
def approve(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] = _value
    log.Approval(msg.sender, _spender, _value)
    return True
