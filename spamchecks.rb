blacklists = ["https://raw.githubusercontent.com/Charcoal-SE/SmokeDetector/master/bad_keywords.txt",
 "https://raw.githubusercontent.com/Charcoal-SE/SmokeDetector/master/blacklisted_websites.txt"
].map do |site|
  Net::HTTP.get_response(URI(site)).body
end

blacklists[0] = blacklists[0].split("\n").map { |i| "\\b#{i}\\b" }.join("\n")

$blacklist = (blacklists.map {|i| i.split("\n")}.flatten - ["", nil]).map do |regex|
  begin
    regex = "(#{regex})" unless regex.include?("(")
    Regexp.new regex unless regex.start_with? '#'
  rescue RegexpError
    puts "Recieved error on #{regex}. Meh..."
    nil
  end
end.reject(&:nil?)

$classifier_thresh = -600

def matches_bl?(text, bl = $blacklist)
  bl.map do |r|
    begin
      if r.is_a?(Regexp) && r.match?(text.to_s.downcase)
        r
      else
        false
      end
    rescue Encoding::CompatibilityError
      #puts "Got an encoding error for #{r}"
      false
    end
  end.select { |i| i }[0]
end

def has_repeated_words(s)
  words = s.split(%r{[\s.,;!/\()\[\]+_-]}).reject { |word| word.to_s.empty? }
  streak = 0
  prev = ""
  words.each do |word|
    (word == prev && word.length > 1) ? streak += 1 : streak = 0
    prev = word
    if streak >= 5 && streak*word.length >= 0.2*s.length
      puts "Repeated word: #{word}"
      return word.to_s
    end
  end
  return false
end

def has_few_characters(s)
  chars = s.split("")
  uniques = s.split("").uniq
  if (chars.length >= 30 && uniques.length <= 6) || (chars.length >= 100 && uniques.length <= 15)
    return "[#{uniques.join(" ")}]"
  else
    return false
  end
end

class String
  def remove_substrs!(arr)
    arr.each { |rem| gsub!(rem, "") }
  end
end

def link_at_end(s)
  s.remove_substrs! ["</strong>", "</em>", "</p>"]
end

def matches_classifier(s)
  $classifier.classify(s) == 'spam'
end

def clean(s)
  # Remove empty lines and code blocks
  s = s.to_s.split("\n").reject do |line|
    line.split("").reject {|char| char.empty?}.empty? ||
    line.start_with?("    ")
  end.join("\n")
  # Replace []() links with text in []. Replace \1 with \2 for links.
  s.gsub!(%r{\[(.*)\]\(([^\b]*)\)},'\1')
  # Remove inline code
  s.gsub!(%r{(\`\b.*\b\`)}, '')
  return s.to_s
end

def reports_for(post)
  rval = []
  #if post.json["body_markdown"].to_s.downcase.include? "thanks"
  #  rval << "Includes 'thanks': [#{post.title}](#{post.link})"
  #end
  if matched_regexp = matches_bl?(post.json["body_markdown"])
    rval << "Blacklisted (#{matched_regexp}): [#{post.title}](#{post.link})"
  end
  if word = has_repeated_words(post.json["body_markdown"])
    rval << "Has repeated words #{word}: [#{post.title}](#{post.link})"
  end
  if chars = has_few_characters(post.json["body_markdown"])
    rval << "Has few unique characters #{chars}: [#{post.title}](#{post.link})"
  end
  std_classified = $classifier.classify_with_score(clean(post.json["body"].to_s))
  if std_classified[0] == 'Spam' && std_classified[1] > $classifier_thresh
    rval << "Matches body classifier (score: #{std_classified[1]}): [#{post.title}](#{post.link})"
  end
  if URI.extract(post.body).map { |u| URI.parse(u).hostname rescue nil }.compact.any? { |i| $domain_classifier.classify(i) == 'Spam' }
    rval << "Matches domain classifier: [#{post.title}](#{post.link})"
  end
  if post.title.to_s.gsub(" ", "").end_with? ","
    rval << "Title ends with comma: [#{post.title}](#{post.link})"
  end
  rval
end
