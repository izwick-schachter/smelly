require 'classifier-reborn'

if File.exists? 'classifier'
  $classifier = Marshal.load(File.read('classifier'))
else
  $classifier = ClassifierReborn::Bayes.new 'spam', 'good'
end

if File.exists? 'domain_bayes'
  $domain_classifier = Marshal.load(File.read('domain_bayes'))
else
  $domain_classifier = ClassifierReborn::Bayes.new('spam', 'good')
end
puts "Clsasifier: #{$classifier}"
puts "DClassifier: #{$domain_classifier}"
