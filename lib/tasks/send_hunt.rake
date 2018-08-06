desc 'Send HUNT Token'
task :send_hunt => :environment do |t, args|
  TEST_MODE = true

  ErcTransaction.pending.each do |t|
    result = JSON.parse(`truffle path/to/script.js`)
    if result['tx_hash']
      t.update! status: 'sent'
    else
      t.update! status: 'error'
      raise result['message']
      # error
    end
  end
end