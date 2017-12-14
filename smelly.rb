require "chatx"
require "se/realtime"
require "se/api"
require "pry"
require "htmlentities"
require "./monkey_patches"
require "./classifier"
require "./spamchecks"

$start = DateTime.now

cb = ChatBot.new("smelly@stackexchange.developingtechnician.com", "smelly#1")
cli = SE::API::Client.new('r7x*BAaM9QwSKcl8b7D3FA((', filter: '!LUcFBHnAma1aXlBRcQnh.U')

cb.login

def load_thresholds
  t = Hash.new {|hsh, key| hsh[key] = 1 }
  YAML.load_file('thresholds.yml').each do |k,v|
    t[k] = v
  end
  t
end

thresholds = load_thresholds

ids = Hash.new {|hsh, key| hsh[key] = []}
posts = Hash.new {|hsh, key| hsh[key] = []}

SE::Realtime.json do |e|
  ids[e[:site]] << e[:id]
  ids.each do |site, post_ids|
    if post_ids.length >= thresholds[site] && !$sleeping
      post_ids = post_ids.join(';')
      ids[site] = []
      cli.posts(post_ids, site: site).each do |post|
        posts[site] << post
        reports_for(post).each do |report|
          puts report
          cb.say(report, 63561)
        end
      end
    end
  end
end

cb.gen_hooks do
  room 63561 do
    on "mention" do |e|
      reply_to e.message, "You called?"
    end
    on "message" do |e|
      say "Yep, alive and well" if e.message.content.downcase == "!!/alive"
    end
    on "message" do |e|
      say "#{cli.quota} requests remaining" if e.message.content.downcase == "!!/quota"
    end
    on "message" do |e|
      say all_posts[e.message.content.split(" ").last.to_i].json["body_markdown"] if e.message.content.downcase.start_with?("!!/see")
    end
    on "message" do |e|
      if e.message.content.downcase.start_with? "!!/allposts"
        posts[e.message.content.downcase.split(" ")[1]].each { |post| say "[#{post.title}](#{post.link})" }
      end
    end
    on "message" do |e|
      say all_posts.length if e.message.content.downcase == "!!/numposts"
    end
    on "message" do |e|
      say File.read("help.txt") if e.message.content.downcase == "!!/help"
    end
    on "message" do |e|
      exit if e.message.content.downcase == "!!/stappit"
    end
    on "message" do |e|
      if e.message.content.downcase.start_with? "!!/test"
        text = HTMLEntities.new.decode(e.message.content.split(" ")[1..-1].join(" "))
        reports = reports_for(SE::API::Post.new({"body_markdown" => text}))
        if reports.empty?
          puts "Would not be caught"
          reply_to e.message, "Would not be caught"
        else
          reports.each do |report|
            puts report
            reply_to(e.message, report)
          end
        end
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/sites"
        say posts.sort_by {|k,v| v.length.to_f / thresholds[k] }.reverse.map { |k,v| "#{k}: #{v.length} (#{v.length.to_f/thresholds[k]})" }.join("\n")
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/rate"
        say cli.quota_used.to_f/((DateTime.now-$start)*24*60)
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/load_thresh"
        say "Reloading..."
        thresholds = load_thresholds
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/uptime"
        say "Up #{((DateTime.now-$start)*24).to_i} hours #{((DateTime.now-$start)*24*60).to_i%60} minutes #{((DateTime.now-$start)*24*60*60).to_i%60} seconds"
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/thresholds"
        say YAML.dump(thresholds)
      end
    end
    on "message" do |e|
      if e.message.content.downcase.start_with? "!!/threshold "
        msg = e.message.content.downcase.split(" ")[1]
        say "The threshold for #{msg} is #{thresholds[msg]}"
      end
    end
    on "message" do |e|
      if e.message.content.downcase.start_with? "!!/set_thresh"
        msg = e.message.content.downcase.split(" ")[1..-1]
        thresholds[msg[0]] = msg[1].to_i
        say "Setting #{msg[0]} to #{msg[1].to_i}. Don't forget to !!/dump_thresh (or !!/load_thresh)"
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/dump_thresh"
        old = File.read('thresholds.yml')
        File.open('thresholds.yml', 'w') { |f| YAML.dump(thresholds.to_a.select { |site,th| th.to_i > 1 }.to_h, f) }
        say "OLD: #{old}\nNew: #{File.read('thresholds.yml')}"
      end
    end
    on "message" do |e|
      case e.message.content.downcase
      when "!!/sleep"
        $sleeping = true
      when "!!/wake"
        $sleeping = false
      when "!!/sleeping?"
        say $sleeping
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/threads"
        say Thread.list.map(&:backtrace).join("\n")
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/ws_test"
        cb.websockets["stackexchange"].driver.close
      end
    end
    on "message" do |e|
      if e.message.content.downcase == "!!/reload_checks"
        load "spamchecks.rb"
        say "Checks reloaded!"
      end
    end
    on "message" do |e|
      case e.message.content.downcase
      when "!!/classify load"
        $classifier = Marshal.load(File.read('classifier'))
        say "Loading classifier from file"
      when "!!/classify dump"
        File.open('classifier', 'w') {|f| f.print(Marshal.dump($classifier)) }
        say "Dumping classifier to file"
      else
        if e.message.content.downcase.start_with? "!!/classify"
          msg = HTMLEntities.new.decode(e.message.content.split(" ")[1..-1].join(" "))
          puts HTMLEntities.new.decode(msg)
          str = %r{\"(.*)\"}.match(msg)[1]
          type = %r{\".*\"\sas\s(\w*)}.match(msg)[1]
          say "Training the classifier to classify '#{str}' as #{type}"
          $classifier.train type, str
        end
      end
    end
  end
end
cb.join_room 63561
