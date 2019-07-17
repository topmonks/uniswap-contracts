# @title Uniswap Exchange Interface V2
# @notice Source code found at https://github.com/uniswap
# @notice Use at your own risk

contract Factory():
    def getExchange(base_addr: address, token_addr: address) -> address: constant

contract Exchange():
    def getBaseToTokenOutputPrice(tokens_bought: uint256) -> uint256: constant
    def baseToTokenTransferInput(base_sold: uint256, min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256: modifying
    def baseToTokenTransferOutput(tokens_bought: uint256, max_base: uint256, deadline: timestamp, recipient: address) -> uint256: modifying

contract Token():
    def balanceOf(_owner: address) -> uint256: constant
    def allowance(_owner: address, _spender: address) -> uint256: constant
    def approve(_spender: address, _value: uint256) -> uint256: modifying
    def transfer(_to: address, _value: uint256) -> bool: modifying
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: modifying


TokenPurchase: event({buyer: indexed(address), base_sold: indexed(uint256), tokens_bought: indexed(uint256)})
BasePurchase: event({buyer: indexed(address), tokens_sold: indexed(uint256), base_bought: indexed(uint256)})
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
token: public(Token)                                        # address of the ERC20 token traded on this contract
factory: public(Factory)                                    # interface for the factory that created this contract

baseToken: public(Token)

# @dev This function acts as a contract constructor which is not currently supported in contracts deployed
#      using create_with_code_of(). It is called once by the factory during contract creation.
@public
def setup(token_addr: address, base_token: address):
    assert (self.factory == ZERO_ADDRESS and self.token == ZERO_ADDRESS) and self.baseToken == ZERO_ADDRESS
    assert token_addr != ZERO_ADDRESS and base_token != ZERO_ADDRESS
    self.factory = Factory(msg.sender)
    self.token = Token(token_addr)
    self.baseToken = Token(base_token)
    self.name = 'Uniswap V2'
    self.symbol = 'UNI-V2'
    self.decimals = 18

# @return Address of Token that is sold on this exchange.
@public
@constant
def tokenAddress() -> address:
    return self.token

# @return Address of Token that is sold on this exchange.
@public
@constant
def baseTokenAddress() -> address:
    return self.baseToken

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
def addLiquidity(base_amount: uint256, max_tokens: uint256, min_liquidity: uint256, deadline: timestamp) -> uint256:
    assert deadline >= block.timestamp and (max_tokens > 0 and base_amount > 0)
    total_liquidity: uint256 = self.totalSupply
    if total_liquidity > 0:
        assert min_liquidity > 0
        token_reserve: uint256 = self.token.balanceOf(self)
        base_reserve: uint256 = self.baseToken.balanceOf(self)
        token_amount: uint256 = base_amount * token_reserve / base_reserve + 1
        liquidity_minted: uint256 = base_amount * total_liquidity / base_reserve
        assert max_tokens >= token_amount and liquidity_minted >= min_liquidity
        self.balanceOf[msg.sender] += liquidity_minted
        self.totalSupply = total_liquidity + liquidity_minted
        successBase: bool = self.baseToken.transferFrom(msg.sender, self, base_amount)
        successToken: bool = self.token.transferFrom(msg.sender, self, token_amount)
        assert successBase and successToken
        # assert self.token.transferFrom(msg.sender, self, token_amount)
        log.AddLiquidity(msg.sender, base_amount, token_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, liquidity_minted)
        return liquidity_minted
    else:
        # TODO: assert msg.value >= 1000000000 equivalent
        assert self.factory != ZERO_ADDRESS and self.token != ZERO_ADDRESS
        assert self.factory.getExchange(self.baseToken, self.token) == self
        token_amount: uint256 = max_tokens
        initial_liquidity: uint256 = as_unitless_number(self.balance)
        self.totalSupply = initial_liquidity
        self.balanceOf[msg.sender] = initial_liquidity
        successBase: bool = self.baseToken.transferFrom(msg.sender, self, base_amount)
        successToken: bool = self.token.transferFrom(msg.sender, self, token_amount)
        assert successBase and successToken
        # assert self.token.transferFrom(msg.sender, self, token_amount)
        log.AddLiquidity(msg.sender, base_amount, token_amount)
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
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_amount: uint256 = amount * base_reserve / total_liquidity
    token_amount: uint256 = amount * token_reserve / total_liquidity
    assert base_amount >= min_base and token_amount >= min_tokens
    self.balanceOf[msg.sender] -= amount
    self.totalSupply = total_liquidity - amount
    baseTransfer: bool = self.baseToken.transfer(msg.sender, token_amount)
    tokenTransfer: bool = self.token.transfer(msg.sender, token_amount)
    assert baseTransfer and tokenTransfer
    # assert self.token.transfer(msg.sender, token_amount)
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

@private
def baseToTokenInput(base_sold: uint256, min_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and (base_sold > 0 and min_tokens > 0)
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_bought: uint256 = self.getInputPrice(base_sold, base_reserve, token_reserve)
    assert tokens_bought >= min_tokens
    baseTransfer: bool = self.baseToken.transferFrom(recipient, self, base_sold)
    tokenTransfer: bool = self.token.transfer(recipient, tokens_bought)
    assert baseTransfer and tokenTransfer
    # assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, base_sold, tokens_bought)
    return tokens_bought

# @notice Convert ETH to Tokens.
# @dev User specifies exact input (msg.value) and minimum output.
# @param min_tokens Minimum Tokens bought.
# @param deadline Time after which this transaction can no longer be executed.
# @return Amount of Tokens bought.
@public
def baseToTokenSwapInput(base_sold: uint256, min_tokens: uint256, deadline: timestamp) -> uint256:
    return self.baseToTokenInput(base_sold, min_tokens, deadline, msg.sender, msg.sender)

# @notice Convert ETH to Tokens and transfers Tokens to recipient.
# @dev User specifies exact input (msg.value) and minimum output
# @param min_tokens Minimum Tokens bought.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output Tokens.
# @return Amount of Tokens bought.
@public
def baseToTokenTransferInput(base_sold: uint256, min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.baseToTokenInput(base_sold, min_tokens, deadline, msg.sender, recipient)

@private
def baseToTokenOutput(tokens_bought: uint256, max_base: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_base > 0)
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_sold: uint256 = self.getOutputPrice(tokens_bought, base_reserve, token_reserve)
    assert max_base >= base_sold
    baseTransfer: bool = self.baseToken.transferFrom(recipient, self, base_sold)
    tokenTransfer: bool = self.token.transfer(recipient, tokens_bought)
    assert baseTransfer and tokenTransfer
    # assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, base_sold, tokens_bought)
    return base_sold

# @notice Convert ETH to Tokens.
# @dev User specifies maximum input (msg.value) and exact output.
# @param tokens_bought Amount of tokens bought.
# @param deadline Time after which this transaction can no longer be executed.
# @return Amount of ETH sold.
@public
def baseToTokenSwapOutput(tokens_bought: uint256, max_base: uint256, deadline: timestamp) -> uint256:
    return self.baseToTokenOutput(tokens_bought, max_base, deadline, msg.sender, msg.sender)

# @notice Convert ETH to Tokens and transfers Tokens to recipient.
# @dev User specifies maximum input (msg.value) and exact output.
# @param tokens_bought Amount of tokens bought.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output Tokens.
# @return Amount of ETH sold.
@public
def baseToTokenTransferOutput(tokens_bought: uint256,  max_base: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.baseToTokenOutput(tokens_bought, max_base, deadline, msg.sender, recipient)

@private
def tokenToBaseInput(tokens_sold: uint256, min_base: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and (tokens_sold > 0 and min_base > 0)
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, base_reserve)
    assert base_bought >= min_base
    baseTransfer: bool = self.token.transfer(recipient, base_bought)
    tokenTransfer: bool = self.token.transferFrom(buyer, self, tokens_sold)
    assert baseTransfer and tokenTransfer
    # assert self.token.transferFrom(buyer, self, tokens_sold)
    log.BasePurchase(buyer, tokens_sold, base_bought)
    return base_bought


# @notice Convert Tokens to ETH.
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_eth Minimum ETH purchased.
# @param deadline Time after which this transaction can no longer be executed.
# @return Amount of ETH bought.
@public
def tokenToBaseSwapInput(tokens_sold: uint256, min_base: uint256, deadline: timestamp) -> uint256:
    return self.tokenToBaseInput(tokens_sold, min_base, deadline, msg.sender, msg.sender)

# @notice Convert Tokens to ETH and transfers ETH to recipient.
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_eth Minimum ETH purchased.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @return Amount of ETH bought.
@public
def tokenToBaseTransferInput(tokens_sold: uint256, min_base: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToBaseInput(tokens_sold, min_base, deadline, msg.sender, recipient)

@private
def tokenToBaseOutput(base_bought: uint256, max_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and base_bought > 0
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_sold: uint256 = self.getOutputPrice(base_bought, token_reserve, base_reserve)
    # tokens sold is always > 0
    assert max_tokens >= tokens_sold
    baseTransfer: bool = self.baseToken.transfer(recipient, base_bought)
    tokenTransfer: bool = self.token.transferFrom(buyer, self, tokens_sold)
    assert baseTransfer and tokenTransfer
    # assert self.token.transferFrom(buyer, self, tokens_sold)
    log.BasePurchase(buyer, tokens_sold, base_bought)
    return tokens_sold

# @notice Convert Tokens to ETH.
# @dev User specifies maximum input and exact output.
# @param eth_bought Amount of ETH purchased.
# @param max_tokens Maximum Tokens sold.
# @param deadline Time after which this transaction can no longer be executed.
# @return Amount of Tokens sold.
@public
def tokenToEthSwapOutput(base_bought: uint256, max_tokens: uint256, deadline: timestamp) -> uint256:
    return self.tokenToBaseOutput(base_bought, max_tokens, deadline, msg.sender, msg.sender)

# @notice Convert Tokens to ETH and transfers ETH to recipient.
# @dev User specifies maximum input and exact output.
# @param eth_bought Amount of ETH purchased.
# @param max_tokens Maximum Tokens sold.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @return Amount of Tokens sold.
@public
def tokenToEthTransferOutput(base_bought: uint256, max_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToBaseOutput(base_bought, max_tokens, deadline, msg.sender, recipient)

@private
def tokenToTokenInput(tokens_sold: uint256, min_tokens_bought: uint256, min_base_bought: uint256, deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert (deadline >= block.timestamp and tokens_sold > 0) and (min_tokens_bought > 0 and min_base_bought > 0)
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, base_reserve)
    assert base_bought >= min_base_bought
    inputTransfer: bool = self.token.transferFrom(buyer, self, tokens_sold)
    assert inputTransfer
    # assert self.token.transferFrom(buyer, self, tokens_sold)
    output_allowance: uint256 = self.baseToken.allowance(self, exchange_addr)
    if base_bought > output_allowance:
        self.baseToken.approve(exchange_addr, base_bought)
    tokens_bought: uint256 = Exchange(exchange_addr).baseToTokenTransferInput(base_bought, min_tokens_bought, deadline, recipient)
    log.BasePurchase(buyer, tokens_sold, base_bought)
    return tokens_bought

# @notice Convert Tokens (self.token) to Tokens (token_addr).
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_tokens_bought Minimum Tokens (token_addr) purchased.
# @param min_eth_bought Minimum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param token_addr The address of the token being purchased.
# @return Amount of Tokens (token_addr) bought.
@public
def tokenToTokenSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_base_bought: uint256, deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(self.baseToken, token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_base_bought, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
#         Tokens (token_addr) to recipient.
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_tokens_bought Minimum Tokens (token_addr) purchased.
# @param min_eth_bought Minimum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @param token_addr The address of the token being purchased.
# @return Amount of Tokens (token_addr) bought.
@public
def tokenToTokenTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_base_bought: uint256, deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(self.baseToken, token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_base_bought, deadline, msg.sender, recipient, exchange_addr)

@private
def tokenToTokenOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_base_sold: uint256, deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_base_sold > 0)
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS
    base_bought: uint256 = Exchange(exchange_addr).getBaseToTokenOutputPrice(tokens_bought)
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_sold: uint256 = self.getOutputPrice(base_bought, token_reserve, base_reserve)
    # tokens sold is always > 0
    assert max_tokens_sold >= tokens_sold and max_base_sold >= base_bought
    success: bool = self.token.transferFrom(buyer, self, tokens_sold)
    assert success
    # assert self.token.transferFrom(buyer, self, tokens_sold)
    output_allowance: uint256 = self.baseToken.allowance(self, exchange_addr)
    if base_bought > output_allowance:
        self.baseToken.approve(exchange_addr, base_bought)
    base_sold: uint256 = Exchange(exchange_addr).baseToTokenTransferOutput(tokens_bought, base_bought, deadline, recipient)
    log.BasePurchase(buyer, tokens_sold, base_bought)
    return tokens_sold

# @notice Convert Tokens (self.token) to Tokens (token_addr).
# @dev User specifies maximum input and exact output.
# @param tokens_bought Amount of Tokens (token_addr) bought.
# @param max_tokens_sold Maximum Tokens (self.token) sold.
# @param max_eth_sold Maximum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param token_addr The address of the token being purchased.
# @return Amount of Tokens (self.token) sold.
@public
def tokenToTokenSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_base_sold: uint256, deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(self.baseToken, token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_base_sold, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (token_addr) and transfers
#         Tokens (token_addr) to recipient.
# @dev User specifies maximum input and exact output.
# @param tokens_bought Amount of Tokens (token_addr) bought.
# @param max_tokens_sold Maximum Tokens (self.token) sold.
# @param max_eth_sold Maximum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @param token_addr The address of the token being purchased.
# @return Amount of Tokens (self.token) sold.
@public
def tokenToTokenTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_base_sold: uint256, deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(self.baseToken, token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_base_sold, deadline, msg.sender, recipient, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token).
# @dev Allows trades through contracts that were not deployed from the same factory.
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_tokens_bought Minimum Tokens (token_addr) purchased.
# @param min_eth_bought Minimum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param exchange_addr The address of the exchange for the token being purchased.
# @return Amount of Tokens (exchange_addr.token) bought.
@public
def tokenToExchangeSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_base_bought: uint256, deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_base_bought, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
#         Tokens (exchange_addr.token) to recipient.
# @dev Allows trades through contracts that were not deployed from the same factory.
# @dev User specifies exact input and minimum output.
# @param tokens_sold Amount of Tokens sold.
# @param min_tokens_bought Minimum Tokens (token_addr) purchased.
# @param min_eth_bought Minimum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @param exchange_addr The address of the exchange for the token being purchased.
# @return Amount of Tokens (exchange_addr.token) bought.
@public
def tokenToExchangeTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_base_bought: uint256, deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_base_bought, deadline, msg.sender, recipient, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token).
# @dev Allows trades through contracts that were not deployed from the same factory.
# @dev User specifies maximum input and exact output.
# @param tokens_bought Amount of Tokens (token_addr) bought.
# @param max_tokens_sold Maximum Tokens (self.token) sold.
# @param max_eth_sold Maximum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param exchange_addr The address of the exchange for the token being purchased.
# @return Amount of Tokens (self.token) sold.
@public
def tokenToExchangeSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_base_sold: uint256, deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_base_sold, deadline, msg.sender, msg.sender, exchange_addr)

# @notice Convert Tokens (self.token) to Tokens (exchange_addr.token) and transfers
#         Tokens (exchange_addr.token) to recipient.
# @dev Allows trades through contracts that were not deployed from the same factory.
# @dev User specifies maximum input and exact output.
# @param tokens_bought Amount of Tokens (token_addr) bought.
# @param max_tokens_sold Maximum Tokens (self.token) sold.
# @param max_eth_sold Maximum ETH purchased as intermediary.
# @param deadline Time after which this transaction can no longer be executed.
# @param recipient The address that receives output ETH.
# @param token_addr The address of the token being purchased.
# @return Amount of Tokens (self.token) sold.
@public
def tokenToExchangeTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_base_sold: uint256, deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_base_sold, deadline, msg.sender, recipient, exchange_addr)

# @notice Public price function for ETH to Token trades with an exact input.
# @param eth_sold Amount of ETH sold.
# @return Amount of Tokens that can be bought with input ETH.
@public
@constant
def getBaseToTokenInputPrice(base_sold: uint256) -> uint256:
    assert base_sold > 0
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_bought: uint256 = self.getInputPrice(base_sold, base_reserve, token_reserve)
    return tokens_bought

# @notice Public price function for ETH to Token trades with an exact output.
# @param tokens_bought Amount of Tokens bought.
# @return Amount of ETH needed to buy output Tokens.
@public
@constant
def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256:
    assert tokens_bought > 0
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_sold: uint256 = self.getOutputPrice(tokens_bought, base_reserve, token_reserve)
    return base_sold

# @notice Public price function for Token to ETH trades with an exact input.
# @param tokens_sold Amount of Tokens sold.
# @return Amount of ETH that can be bought with input Tokens.
@public
@constant
def getTokenToBaseInputPrice(tokens_sold: uint256) -> uint256:
    assert tokens_sold > 0
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    base_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, base_reserve)
    return base_bought

# @notice Public price function for Token to ETH trades with an exact output.
# @param eth_bought Amount of output ETH.
# @return Amount of Tokens needed to buy output ETH.
@public
@constant
def getTokenToEthOutputPrice(base_bought: uint256) -> uint256:
    assert base_bought > 0
    base_reserve: uint256 = self.baseToken.balanceOf(self)
    token_reserve: uint256 = self.token.balanceOf(self)
    tokens_sold: uint256 = self.getOutputPrice(base_bought, token_reserve, base_reserve)
    return tokens_sold

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
