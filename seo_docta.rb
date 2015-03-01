require 'json'
require 'nokogiri'
require 'open-uri'
require 'pry-byebug'
require 'fastimage'

class PageSeo
  CITY_NAME = 'singapore'
  MAX_LENGTH_ANCHOR_TEXT = 4

  def initialize(url)
    ##
    ## Retrieve the web page
    ##
    puts "Opening url #{url} ..."
    @url = url
    page = open url
    @uri = Addressable::URI.parse(@url)
    @host = @uri.host
    @path = @uri.path

    ##
    ## Load the page in Nokogiri Document & Google Stop Words list
    ##
    @doc = Nokogiri::HTML(page)
    @stop_words = get_stop_words_list("stop_words.txt")
  end

  def run_report(media = 'console')
    ##
    ## Assemble Report & Print it
    ##
    puts "Starting SEO report ..."

    if media == 'file'
      filename = "reports/#{@uri.host}#{@uri.path.gsub('/', '_')}.txt"
      @output = File.open(filename, 'w')
        seo_elements_report
      @output.close
      puts "Report file written at #{filename}"
    else
      @output = ::Kernel
      seo_elements_report
    end
  end

  def seo_elements_report
    url_report
    title_report
    meta_report
    h1_report
    h2_report
    images_report
    content_report
    keyword_report
    link_report
  end

  def url_report
    analyze 'U R L' do |elements, report|
      elements << @url
      report[:error] << 'Should not have dynamic segment with digits' if @url =~ /\/\d+\//  # post/25/
      report[:error] << "Should not have encoded sign '%' with digits" if @url =~ /%\d+/  # %23
      report[:error] << 'Should have dash instead of underscore'  if @url =~ /_/  # _
      report[:info] << 'URL contains only recommended characters' if report[:error].empty?
      #TODO Check occurences of the keyword
    end
  end

  def title_report
    analyze 'T I T L E' do |elements, report|
      title = @doc.xpath('//title')
      if title.size < 1
        report[:error] << 'Should have a title.'
        elements << 'NO TITLE'
        next
      elsif title.size > 1
        report[:error] << 'Should not be more than one title.'
        elements << 'MULTIPLE TITLE'
        next
      end
      @title = title.first.content.strip
      if @title.size > 65
        report[:warning] << "Should not have more than 65 Characters. There is '#{@title.size}'. Except if you aim multiple keywords within this page, reduce the size."
      else
        report[:info] << "The title has a length of: #{@title.size} characters (65 Max recommended)." if ( report[:error].empty? &&  report[:warning].empty?)
      end
      #TODO Check keyword at beginning
      elements << @title
    end
  end

  def meta_report
    analyze 'M E T A' do |elements, report|
      meta_keyword = @doc.xpath("//meta[@name='keywords']/@content")
      meta_description = @doc.xpath("//meta[@name='description']/@content").to_s.strip
      if meta_keyword.size < 1
         report[:info] << 'There is no meta keywords.'
      else
         report[:info] << "These are the Meta Keywords: #{meta_keyword}."
      end
      if meta_description.size < 1
        report[:error] << "Should have Meta Description except if you are targeting multiple keywords."
        elements << 'NO META DESCRIPTION'
        next
      end
      @meta_description = [] << meta_description
      if meta_description.size > 160
        report[:warning] << "Should not have more than '160' character. There is: '#{meta_description.size}'."
      else
        report[:info] << "The Meta Description has a length of: #{meta_description.size} characters (160 Max recommended)."
      end
      elements.concat @meta_description
    end
  end

  def h1_report
    analyze 'H 1' do |elements, report|
      h1 = @doc.xpath('//h1')
      if h1.size < 1
        report[:error] << 'Should have at least one H1.'
        elements << 'NO H1'
        next
      end
      @h1 = []
      h1.each do |h|
        @h1 << h.content
      end
      report[:info] << "There is '#{h1.count}' H1 tag(s)." if report[:error].empty?
      #TODO Check keyword in h1 especially first
      elements.concat @h1
    end
  end

  def h2_report
    analyze 'H 2' do |elements, report|
      h2 = @doc.xpath('//h2')
      if h2.size < 1
        report[:info] << 'There is no H2.'
        elements << 'NO H2'
        next
      end
      @h2 = []
      h2.each do |h|
        @h2 << h.content
      end
      report[:info] << "You have #{h2.count} H2 tag(s)." if report[:error].empty?
      #TODO Check keyword in h2
      elements.concat @h2
    end
  end

  def images_report
    analyze 'I M A G E' do |elements, report|
      images = @doc.xpath("/html/body//img")
      if images.size < 3
        report[:warning] << 'It would be nice to have 3 images or more.'
      elsif images.size < 1
        report[:error] << 'Should have at least 1 image.'
        elements << 'NO IMAGES'
        next
      end
      @images = []
      images.each do |image|
        source = image.attribute("src").content
        img_uri = Addressable::URI.parse(source)
        #TODO MultiThreading img_size = FastImage.size(source) || [0,0]

        hidden_image = !!( image.attribute("style") && image.attribute("style").content.include?('display:none') )
        unless ( image.attribute("alt") && !image.attribute("alt").content.empty? )
          report[:error] << "Should have an alternative text: '#{source}'"
          next
        end
        @images << [
          ( hidden_image ? "HIDDEN #{source}" : File.basename(img_uri.path, '.*') ),
          image.attribute("alt").content,
          #TODO MultiThreading img_size[0] * img_size[1]
        ]
      end
      report[:info] << "You have '#{images.size}' images and they all have alternate texts." if ( report[:error].empty? &&  report[:warning].empty? )
      #@images.sort_by{|img| img[2]}
      #TODO Check keyword in images
      elements.concat @images
    end
  end

  def content_report
    analyze 'C O N T E N T' do |elements, report|
      @doc.search('script,noscript').remove
      content = @doc.xpath('//text()').map(&:content).delete_if{|x| x !~ /\w/}
      if content.size < 1
        report[:error] << 'There is no content.'
        elements << 'NO CONTENT'
        next
      end
      content_words = content.join(' ').split
        .map(&:downcase)
        .map{|w| w.gsub('’', '\'')}
        .map{|w| w.gsub(/[^a-z\']/, '')}
        .delete_if{|w| w !~ /[a-z]/}
      content_words = trim_stop_words(content_words)
      words_frequency = Hash.new(0)
      content_words.each { |word| words_frequency[word] += 1 }
      top_15 = words_frequency.sort_by{|k,v| -v}[0..14].to_h
      @content = [] << ['Total page word count: ', content.join.split.size]
      @content << ['Average word length: ', (content.join.size / content.join.split.size)]
      paragraphs_word_count = @doc.xpath('//p').map(&:content).join.split.size
      @content << ['Paragraphs word count: ', paragraphs_word_count]
      @content << ['Top 15 used words', top_15]
      if paragraphs_word_count < 300
        report[:error] << "Should have at least 300 words of content on the page paragraphs. (500 words recommended)"
      elsif paragraphs_word_count < 500
        report[:warning] << "It would be nicer to have over 500 words of content on the page paragraphs."
      end
      report[:info] << "There is over 500 words of content on the page paragraphs." if ( report[:error].empty? &&  report[:warning].empty? )
      #TODO Check keyword in content
      elements.concat @content
    end
  end

  def keyword_report
    analyze 'K E Y W O R D' do |elements, report|
      possible_keywords = [].push(*@h1).push(@title).push(@meta_description).join(' ')
        .split
        .map(&:downcase)
        .map{|w| w.gsub('’', '\'')}
        .map{|w| w.gsub(/[^a-z\']/, '')}
        .delete_if{|w| w !~ /[a-z]/}
        .uniq
      possible_keywords = trim_stop_words(possible_keywords)
      @possible_keywords = possible_keywords
      all_words = @doc.xpath('//text()').map{|c| c.content.split}.flatten.map(&:downcase).delete_if{|x| x !~ /[a-z]/}
      counting = Hash[possible_keywords.map {|v| [v,0]}]
      all_words.each do |word|
        if possible_keywords.include? word
          counting[word] += 1
        end
      end
      keyword_occurences = counting.sort_by {|_, v| v}.reverse.to_h.inject({}){|h, (k,v)| h[k]="#{v} (#{percentage(v, 521)}%)"; h}
      @keywords = [] << ['Keywords for this page might be among these: ', possible_keywords]
      bold_words = @doc.xpath("//strong")
      unless bold_words.empty?
        @keywords << ["There are #{bold_words.size} strong words", bold_words.map(&:content)]
      else
        report[:info] << "There are no strong words (bold) at all in this page."
      end
      emphasized_words = @doc.xpath("//em")
      unless emphasized_words.empty?
        @keywords << ["There are #{emphasized_words.size} emphasized words", emphasized_words.map(&:content)]
      else
        report[:info] << "There are no emphasized words (italic) at all in this page."
      end
      report[:info] << "Keywords occurences are: #{keyword_occurences}"
      elements.concat @keywords
    end
  end

  def link_report
    analyze 'L I N K' do |elements, report|
      links = @doc.xpath('//a')
      if links.size < 2
        report[:error] << 'Should have at least a couple of links pointing to an internal page.'
        elements << 'NO LINKS'
        next
      end
      @links = []
      wordy_count = 0
      wordy_words = []
      city_count = 0
      kw_count = 0
      home_link_count = 0
      internal_links_footer_count = 0
      links.each do |a|
        if a.attribute("href").nil?
          report[:error] << "This anchor text should have have a URL to point to. Do not use Flash or JS but text link for changing page instead of: \n #{a} \n"
          next
        else
          url = a.attribute("href").content.strip
        end
        link_uri = Addressable::URI.parse(url)
        if a.xpath('img').empty?
          anchor_text = a.content.strip
          @links << [anchor_text, link_display(link_uri)]
        else
          first_image = a.xpath('img').first
          anchor_text = first_image.attribute("alt").nil? ? '' : first_image.attribute("alt").content.strip
          @links << ['IMAGE = ' + anchor_text, link_display(link_uri)]
        end
        if anchor_text.split.size > MAX_LENGTH_ANCHOR_TEXT
          wordy_count += 1
          wordy_words << anchor_text
        end
        city_count += 1 if anchor_text.downcase.include? CITY_NAME
        kw_count += 1 if @possible_keywords.any? { |word| anchor_text.downcase.include?(word) }
        home_link_count += 1 if link_uri.path =~ /(\A\/\z|\A\/#)/
      end
      footer_links = @doc.xpath("//footer//a")
      footer_links.each do |a|
        link_uri = Addressable::URI.parse(a.attribute("href"))
        internal_links_footer_count += 1 if ( (@uri.host == link_uri.host) || link_uri.host.nil? )
      end
      links_count = links.size

      # Links should be descriptive and too long i.e:4 characters
      if wordy_count > 0
        report[:warning] << "There are '#{wordy_count}' (#{percentage(wordy_count, links_count)}%) anchor texts that are exceeding #{MAX_LENGTH_ANCHOR_TEXT} characters.
          --> #{wordy_words}"
      else
        report[:info] << "All the anchor texts are less than #{MAX_LENGTH_ANCHOR_TEXT} characters. Anchor texts should stay descriptive though."
      end

      # Links containing local city name
      if city_count > 0
        report[:info] << "There are '#{city_count}' (#{percentage(city_count, links_count)}%) anchor texts with city name '#{CITY_NAME}'."
      else
        report[:warning] << "There are no anchor texts with city name '#{CITY_NAME}'."
      end

      # Links containing keywords
      if kw_count > 0
        report[:info] << "There are '#{kw_count}' (#{percentage(kw_count, links_count)}%) anchor texts that contains the possible keywords."
      else
        report[:warning] << "There are no anchor texts that contains the possible keywords."
      end

      # Home page links
      if home_link_count > 0
        report[:info] << "There are '#{home_link_count}' (#{percentage(home_link_count, links_count)}%) anchor texts pointing to Home page."
      else
        report[:warning] << "There are no anchor texts pointing to Home page."
      end

      # Internal Links in the footer
      if internal_links_footer_count > 0
        report[:info] << "There are '#{internal_links_footer_count}' (#{percentage(internal_links_footer_count, links_count)}%) internal anchor texts in the footer.
          #{percentage(internal_links_footer_count, footer_links.size)}% of the footer links are internals (the more the better)."
      else
        report[:warning] << "There are no internal anchor texts in the footer."
      end

      report[:info] << "Total of '#{links.size}' anchor texts with '#{internal_links_count}' internal links."
      elements.concat @links
    end
  end

  #
  # Helper methods
  #
  def internal_links_count(value = nil)
    @internal_links_count ||= 0
    if value
      @internal_links_count += value
    end
    @internal_links_count
  end

  def link_display(link_uri)
    if( (@uri.host == link_uri.host) || link_uri.host.nil? )
      internal_links_count(1)
      link_uri.path.to_s
    else
      "EXTERNAL #{link_uri.to_s}"
    end
  end

  def get_stop_words_list(filename)
    list = []
    File.read(filename).each_line do |line|
      list << line.chop
    end
    list
  end

  def trim_stop_words(list = [])
    list - @stop_words
  end

  def percentage(value, total_value)
    ((value.to_f / total_value.to_f) *100).round(1)
  end

  #
  # Setup reporting structure Hash
  #
  def analyze(name)
    report = {error: [], warning: [], info: [], good: []}
    elements = []
    yield(elements, report)
    display(name, elements, report)
  end

  #
  # Display the report for Console or Text file
  #
  def display(name, elements, report)
    printer name do |line|
      elements.each do |element|
        if element.is_a?(Array)
          @output.print "#{element[0]}"
          @output.puts " --> '#{element[1]}' \n"
        else
          @output.puts "#{element} \n"
        end
      end
      @output.puts "#{line} \n"
      report.each do |key, value|
        next if value.empty?
        @output.puts "  = #{key.to_s.upcase} : "
        value.each do |msg|
          @output.puts "   - #{msg}"
        end
      end
    end
  end

  def printer(name)
    header = "\n\n=================================================== #{name} ==================================================="
    footer = header.chars.map{|c| '='}
    footer.pop 2
    footer = footer.join
    sub_header = footer.chars.each_with_index.map{|c,i| i.even? ? '-' : ' '}
    sub_header = sub_header.join

    @output.puts header
    yield sub_header
    @output.puts "#{footer} \n\n"
  end
end

p = PageSeo.new(ARGV[0])
p.run_report(ARGV[1])
