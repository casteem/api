desc 'Send HUNT Token'
task :send_hunt => :environment do |t, args|
  TEST_MODE = true
  NETWORK = TEST_MODE ? 'ropsten' : 'mainnet'
  GAS_PRICE = 20.1

  ErcTransaction.pending.each do |t|
    if t.pending?
      t.update! status: 'running'
    else
      raise 'INVALID_STATUS'
    end

    puts "Sending #{t.amount} HUNTs to @#{t.user.username}: #{t.user.eth_address}"

    out = `cd #{Rails.root}/../hunt/HuntToken && truffle exec scripts/airdrop.js --network #{NETWORK} address="#{t.user.eth_address}" amount=#{t.amount} gas_price=#{GAS_PRICE}`
    result = JSON.parse(out.split.last)
    puts "https://ropsten.etherscan.io/tx/#{result['tx_hash']}"

    if result['tx_hash']
      t.update! status: 'sent', tx_hash: result['tx_hash']
    else
      t.update! status: 'error'
      raise result['message']
      # error
    end
  end
end