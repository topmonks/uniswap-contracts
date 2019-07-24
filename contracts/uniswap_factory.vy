struct Pair:
    tokenA: address
    tokenB: address

contract Exchange():
    def setup(token_addr: address, base_addr: address): modifying

NewExchange: event({token: indexed(address), baseToken: indexed(address), exchange: indexed(address)})

exchangeTemplate: public(address)
exchangeCount: public(uint256)
getExchange: public(map(address, map(address, address)))        # map(baseToken, map(token, exchange))
getPair: map(address, Pair)                                     # map(exchange, token)
getBase: public(map(address, address))                          # map(exchange, baseToken)
getExchangeWithId: public(map(uint256, address))                # map(id, exchange)



@public
def initializeFactory(template: address):
    assert self.exchangeTemplate == ZERO_ADDRESS
    assert template != ZERO_ADDRESS
    self.exchangeTemplate = template

@public
def createExchange(token1: address, token2: address) -> address:
    template: address = self.exchangeTemplate
    assert template != ZERO_ADDRESS and token1 != token2
    assert token1 != ZERO_ADDRESS and token2 != ZERO_ADDRESS

    tokenA: address = ZERO_ADDRESS
    tokenB: address = ZERO_ADDRESS
    value1: uint256 = convert(token1, uint256)
    value2: uint256 = convert(token2, uint256)

    if value1 < value2:
        tokenA = token1
        tokenB = token2
    else:
        tokenA = token2
        tokenB = token1

    assert self.getExchange[tokenA][tokenB] == ZERO_ADDRESS
    exchange: address = create_forwarder_to(self.exchangeTemplate)
    Exchange(exchange).setup(tokenA, tokenB)

    self.getExchange[tokenA][tokenB] = exchange
    self.getPair[exchange].tokenA = tokenA
    self.getPair[exchange].tokenB = tokenB

    exchange_id: uint256 = self.exchangeCount + 1
    self.exchangeCount = exchange_id
    self.getExchangeWithId[exchange_id] = exchange

    log.NewExchange(tokenA, tokenB, exchange)
    return exchange
