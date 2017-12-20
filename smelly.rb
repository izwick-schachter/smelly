require "chatx"
require "se/realtime"
require "se/api"
require "pry"
require "htmlentities"
require "./monkey_patches"
require "./classifier.rb"
require "./spamchecks"

$start = DateTime.now

cb = ChatBot.new(ENV['ChatXUsername'], ENV['ChatXPassword'])
cli = SE::API::Client.new('r7x*BAaM9QwSKcl8b7D3FA((')

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

$mid_p = {}

$ignored_sites = %w[
ru.stackoverflow
es.stackoverflow
japanese
rus
german
pt.stackoverflow
spanish
]

SE::Realtime.json do |e|
  next if $ignored_sites.include? e[:site]
  ids[e[:site]] << e[:id]
  ids.each do |site, post_ids|
    if post_ids.length >= thresholds[site] && !$sleeping
      ids[site] = []
      cli.questions(post_ids, site: site).each do |post|
        q_and_a = post.answers.push(post)
        puts "==========================================="
        q_and_a.each do |p|
          puts "#{p.class} #{p.last_activity_date} #{p.title}"
        end
        puts "==========================================="
        post = q_and_a.sort_by { |p| p.last_activity_date }.first
        posts[site] << q_and_a
        reports_for(post).each do |report|
          puts report
          mid = cb.say(report, 63561)
          $mid_p[mid] = post 
        end
      end
    end
  end
end

$admins = [162795]

cb.gen_hooks do
  room 63561 do
    say "Starting up..."
    on "mention" do |e|
      reply_to e, "You called?"
    end
    command("!!/alive")    { say "Yep, alive and well" }
    command("!!/quota")    { say "#{cli.quota} requests remaining" }
    command("!!/numposts") { say posts.values.flatten.length }
    command("!!/help")     { say File.read('help.txt') }
    on "message" do |e|
      if e.content.downcase.start_with? "!!/powah?"
        if $admins.include? e.user_id.to_i
          reply_to e, "You have powah!"
        else
          reply_to e, "You don't have powah!"
        end
      end
    end
    on "message" do |e|
      if e.content.downcase.start_with? "!!/stappit"
        if $admins.include? e.user.id.to_i
          say "Stapping it"
          exit
        else
          reply_to e, "You can't stop me!"
        end
      end
    end
    on "message" do |msg|
      if msg.content.downcase.start_with? "!!/test"
        text = HTMLEntities.new.decode(msg.content.split(" ")[1..-1].join(" "))
        reports = reports_for(SE::API::Post.new({"body_markdown" => text, "body" => text, "title" => text}))
        if reports.empty?
          puts "Would not be caught"
          reply_to msg, "Would not be caught"
        else
          reports.each do |report|
            puts report
            reply_to(msg, report)
          end
        end
      end
    end
    command "!!/sites" do
      say posts.sort_by {|k,v| v.length.to_f / thresholds[k] }.reverse.map { |k,v| "#{k}: #{v.length} (#{v.length.to_f/thresholds[k]})" }.join("\n")
    end
    command("!!/rate")        { say cli.quota_used.to_f/((DateTime.now-$start)*24*60) }
    command("!!/load_thresh") { say "Reloading..."; thresholds = load_thresholds }
    command("!!/uptime")      { say "Up #{((DateTime.now-$start)*24).to_i} hours #{((DateTime.now-$start)*24*60).to_i%60} minutes #{((DateTime.now-$start)*24*60*60).to_i%60} seconds" }
    command("!!/thresholds")  { say YAML.dump(thresholds) }
    command("!!/threshold")   { |site| say "The threshold for #{site} is #{thresholds[site]}" }
    command("!!/set_thresh")  { |site, new_thresh| thresholds[site] = new_thresh.to_i; say "Setting #{site} to #{thresholds[site]}. Don't forget to !!/dump_thresh (or !!/load_thresh)" }
    command "!!/dump_thresh" do
      old = File.read('thresholds.yml')
      File.open('thresholds.yml', 'w') { |f| YAML.dump(thresholds.to_a.select { |site,th| th.to_i > 1 }.to_h, f) }
      say "Old:\n#{old}\nNew:\n#{File.read('thresholds.yml')}"
    end
    command("!!/sleep")         { $sleeping = true; say "Am asleep? #{$sleeping}" }
    command("!!/wake")          { $sleeping = false;say "Am asleep? #{$sleeping}" }
    command("!!/sleeping")      { say $sleeping }
    command("!!/ws_test")       { cb.websockets["stackexchange"].driver.close }
    command("!!/reload_checks") { load "spamchecks.rb"; say "Checks reloaded!" }
    command "!!/classify" do |cmd, _as, val|
      case cmd.downcase
      when "load"
        $classifier = Marshal.load(File.read('classifier'))
        say "Loading classifier from file"
      when "dump"
        File.open('classifier', 'w') {|f| f.print(Marshal.dump($classifier)) }
        say "Dumping classifier to file"
      else
        puts val
        str = cmd
        type = val
        say "Training the classifier to classify '#{str}' as #{type}"
        $classifier.train type, str
      end
    end
    command "!!/classifier_thresh" do |thresh|
      $classifier_thresh = thresh.to_f
      say "Setting classifier threshold to #{$classifier_thresh}"
    end
    command "!!/ping" do |user, *msg|
      say "@#{user} #{msg.join(" ")}"
    end
  end
end
cb.join_room 63561
