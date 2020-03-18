require 'highline/import'
require 'mechanize'
require 'openssl'
require 'json'

# Disable SSL verify
I_KNOW_THAT_OPENSSL_VERIFY_PEER_EQUALS_VERIFY_NONE_IS_WRONG = nil
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

# Grabbed from https://github.com/decomoji/slack-reaction-decomoji/blob/fd1f9b6a12b95ee27b9ad4173560db9ae3015ea0/scripts/import.rb
class Uploader
  def initialize(dir)
    @dir = dir
    @page = nil
    @agent = Mechanize.new
  end
  attr_accessor :page, :agent, :team_name, :token

  def upload_emojis
    go_to_emoji_page
    push_emojis
  end

  private

  def login
    @team_name = ask('Your slack team name: ')
    email      = ask('Login email: ')
    password   = ask('Login password(hidden): ') { |q| q.echo = false }

    emoji_page_url = "https://#{@team_name}.slack.com/customize/emoji"

    page = agent.get(emoji_page_url)
    page.form.email = email
    page.form.password = password
    @page = page.form.submit
    @token = @page.body[/(?<=api_token":")[^"]+/]
  end

  def bypass_two_step_authen_code
    page.form['2fa_code'] = ask('Please enter your 2-step authen code: ')
    @page = page.form.submit
    @token = @page.body[/(?<=api_token":")[^"]+/]
  end

  def go_to_emoji_page
    loop do
      if page && page.form['signin_2fa']
        bypass_two_step_authen_code
      else
        login
      end

      break if page.title.include?('Emoji')

      puts 'Login fail, please try again.'
    end
  end

  def push_emojis
    emojis = list_emojis
    Dir.glob("#{@dir}/*.{jpg,png,gif,jpeg}").each do |path|
      basename = File.basename(path, '.*')

      # skip if already exists
      if emojis.include?(basename)
        puts "Already exist #{basename} emoji :("
        next
      end

      puts "importing #{basename}..."
      params = {
        name: basename,
        image: File.new(path),
        mode: 'data',
        token: token
      }
      agent.post("https://#{@team_name}.slack.com/api/emoji.add", params)
    end
  end

  def list_emojis
    emojis = []
    loop.with_index(1) do |_, n|
      params = { query: '', page: n, count: 100, token: token }
      res = JSON.parse(agent.post("https://#{@team_name}.slack.com/api/emoji.adminList", params).body)
      raise res['error'] if res['error']

      emojis.push(*res['emoji'].map { |e| e['name'] })
      break if res['paging']['pages'] == n || res['paging']['pages'] == 0
    end
    emojis
  end
end

dir = ask("Pls enter the path to emojis folder, 'q' for current folder: ")
dir = Dir.pwd if dir.downcase.strip == 'q'

Uploader.new(dir).upload_emojis
