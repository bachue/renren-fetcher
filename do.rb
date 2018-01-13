require 'bundler/setup'
require 'rest-client'
require 'rack/utils'
require 'json'
require 'sqlite3'
require 'logger'

RestClient.log = Logger.new(STDERR)
AUTHORIZATION = 'Bearer 599515|6.d0c33ce3378ef87d1f0797dff29ab898.2592000.1518073200-261589993'.freeze

abort "Usage: $#0 DBFILE" if ARGV.length == 0
dbfile = ARGV[0]

DB = SQLite3::Database.new(dbfile)

def put_user_info id
  result = DB.query 'SELECT COUNT(*) FROM users WHERE id = ?;', [id]
  if result.next_hash.fetch('COUNT(*)', 0).zero?
    begin
      sleep 30
      response = RestClient.get 'https://api.renren.com/v2/user/get?' + Rack::Utils.build_query(userId: id), 'Authorization': AUTHORIZATION
      data = JSON.parse(response)['response']
      DB.execute('INSERT INTO users(id, name, sex, birthday) VALUES(?, ?, ?, ?);', data['id'], data['name'], data.dig('basicInformation', 'sex'), data.dig('basicInformation', 'birthday'))
    rescue RestClient::Exception => e
      STDERR.puts e.response
    end
  end
ensure
  result.close
end

def fetch_list name, args
  response = RestClient.get "https://api.renren.com/v2/#{name}/list?" + Rack::Utils.build_query(args), 'Authorization': AUTHORIZATION
  JSON.parse(response)['response']
rescue RestClient::Exception => e
  STDERR.puts e.response
end

fetch_list('comment', entryOwnerId: 414979621, entryId: 3342016142, commentType: 'STATUS', pageNumber: 1, pageSize: 20).each do |comment|
  puts "#{comment['id']} => #{comment['content']}"
  fields = %w[id content time commentType entryId entryOwnerId authorId]
  DB.execute("INSERT INTO comments(#{fields.join(', ')}) VALUES(#{fields.map {'?'}.join(', ')});", comment.values_at(*fields))
  put_user_info comment['authorId']
rescue => e
  STDERR.puts e.message
  e.backtrace.each do |trace|
    STDERR.puts "  #{trace}"
  end
end
