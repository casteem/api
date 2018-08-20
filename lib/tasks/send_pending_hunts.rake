desc 'Send all pending HUNT token withdrawals'
task :send_pending_hunts => :environment do |t, args|
  TEST_MODE = true
  NETWORK = TEST_MODE ? 'ropsten' : 'mainnet'

  uri = URI('https://www.etherchain.org/api/gasPriceOracle')
  response = Net::HTTP.get(uri)
  json = JSON.parse(response)
  GAS_PRICE = json['safeLow'].to_f

  puts "Set gas price: #{GAS_PRICE} GWei"

  ErcTransaction.pending.each do |t|
    if t.pending?
      t.update! status: 'running'
    else
      raise 'INVALID_STATUS'
    end

    eth_address = "0x4fb5fffc08c1b6d6f0a841159e2685e3132c3e04" # t.user.eth_address
    puts "Sending #{t.amount} HUNTs to @#{t.user.username}: #{eth_address}"

    out = `cd #{Rails.root}/../hunt && truffle exec scripts/airdrop.js --network #{NETWORK} address="#{eth_address}" amount=#{t.amount} gas_price=#{GAS_PRICE}`
    begin
      result = JSON.parse(out.split.last)
    rescue => e
      puts "ERC transaction failed: #{out}"
      raise
    end

    puts "-> https://ropsten.etherscan.io/tx/#{result['tx_hash']}"

    if result['tx_hash']
      t.update! status: 'sent', tx_hash: result['tx_hash']
    else
      t.update! status: 'error'
      raise result['message']
      # error
    end
  end
end