require 'bundler/setup'
require 'rest-client'
require 'rack/utils'
require 'json'
require 'sqlite3'
require 'logger'

BachueId = 261589993.freeze
ElicierId = 414979621.freeze
AUTHORIZATION = 'Bearer 599515|6.d0c33ce3378ef87d1f0797dff29ab898.2592000.1518073200-261589993'.freeze

RestClient.log = Logger.new(STDERR)

DB = SQLite3::Database.new("#{Time.now.strftime('%F %T')}.db")

DB.execute <<~SQL
CREATE TABLE blogs(id INT, ownerId INT, type VARCHAR, title VARCHAR, content VARCHAR, shareCount INT, accessControl VARCHAR, viewCount INT, commentCount INT);
SQL
DB.execute <<~SQL
CREATE TABLE statuses(id INT, ownerId INT, content VARCHAR, createTime VARCHAR, shareCount INT, commentCount INT, sharedStatusId INT, sharedUserId INT);
SQL
DB.execute <<~SQL
CREATE TABLE comments(id INT, content VARCHAR, time VARCHAR, commentType VARCHAR, entryId INT, entryOwnerId INT, authorId INT);
SQL
DB.execute <<~SQL
CREATE TABLE users(id INT, name VARCHAR, sex VARCHAR, birthday VARCHAR);
SQL

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

def fetch_all_list name, args
  pageNo = 1
  pageSize = 20
  results = []
  loop do
    sleep 30
    entries = fetch_list name, args.update(pageNumber: pageNo, pageSize: pageSize)
    pageNo += 1
    break if entries.size == 0
    results += entries
    break if entries.size < pageSize
  rescue RestClient::Exception => e
    STDERR.puts e.response
  end
  results
end

def fetch_all_comments commentType, entryId, entryOwnerId
  fetch_all_list 'comment', entryOwnerId: entryOwnerId, entryId: entryId, commentType: commentType
end

def fetch_for ownerId
  blogs = fetch_all_list('blog', ownerId: ownerId)
  blogs.each do |blog|
    fields = %w[id ownerId type title content shareCount accessControl viewCount commentCount]
    DB.execute("INSERT INTO blogs(#{fields.join(', ')}) VALUES(#{fields.map {'?'}.join(', ')});", blog.update('ownerId' => ownerId).values_at(*fields))
  end
  blogs = blogs.select { |r| r['commentCount'] > 0 }

  blogs.each do |blog|
    fetch_all_comments('BLOG', blog['id'], ownerId).each do |comment|
      fields = %w[id content time commentType entryId entryOwnerId authorId]
      DB.execute("INSERT INTO comments(#{fields.join(', ')}) VALUES(#{fields.map {'?'}.join(', ')});", comment.values_at(*fields))
      put_user_info comment['authorId']
    end
  end

  statuses = fetch_all_list('status', ownerId: ownerId)
  statuses.each do |status|
    fields = %w[id ownerId content createTime shareCount commentCount sharedStatusId sharedUserId]
    DB.execute("INSERT INTO statuses(#{fields.join(', ')}) VALUES(#{fields.map {'?'}.join(', ')});", status.values_at(*fields))
  end
  statuses = statuses.select { |r| r['commentCount'] > 0 }

  statuses.each do |status|
    fetch_all_comments('STATUS', status['id'], ownerId).each do |comment|
      fields = %w[id content time commentType entryId entryOwnerId authorId]
      DB.execute("INSERT INTO comments(#{fields.join(', ')}) VALUES(#{fields.map {'?'}.join(', ')});", comment.values_at(*fields))
      put_user_info comment['authorId']
    end
  end
end

fetch_for ElicierId
fetch_for BachueId
