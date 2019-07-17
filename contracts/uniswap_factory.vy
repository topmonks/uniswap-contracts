contract Exchange():
    def setup(token_addr: address, base_addr: address): modifying

NewExchange: event({token: indexed(address), baseToken: indexed(address), exchange: indexed(address)})

exchangeTemplate: public(address)
# tokenCount: public(uint256)
# getExchange: public(map(address, address))
# getToken: public(map(address, address))
# getTokenWithId: public(map(uint256, address))

exchangeCount: public(uint256)
getExchange: public(map(address, map(address, address)))        # map(baseToken, map(token, exchange))
getToken: public(map(address, address))                         # map(exchange, token)
getBase: public(map(address, address))                          # map(exchange, baseToken)
getExchangeWithId: public(map(uint256, address))                # map(id, exchange)

@public
def initializeFactory(template: address):
    assert self.exchangeTemplate == ZERO_ADDRESS
    assert template != ZERO_ADDRESS
    self.exchangeTemplate = template

@public
def createExchange(token: address, baseToken: address) -> address:
    assert token != ZERO_ADDRESS and baseToken != ZERO_ADDRESS
    assert self.exchangeTemplate != ZERO_ADDRESS
    assert self.getExchange[baseToken][token] == ZERO_ADDRESS
    exchange: address = create_forwarder_to(self.exchangeTemplate)
    Exchange(exchange).setup(token, baseToken)
    self.getExchange[baseToken][token] = exchange
    self.getToken[exchange] = token
    self.getBase[exchange] = token
    exchange_id: uint256 = self.exchangeCount + 1
    self.exchangeCount = exchange_id
    self.getExchangeWithId[exchange_id] = exchange
    log.NewExchange(token, baseToken, exchange)
    return exchange
