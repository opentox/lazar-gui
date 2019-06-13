helpers do

  def embedded_svg image, options={}
    doc = Nokogiri::HTML::DocumentFragment.parse image
    svg = doc.at_css 'svg'
    title = doc.at_css 'title'
    if options[:class].present?
      svg['class'] = options[:class]
    end
    if options[:title].present?
      if options[:title] == "x"
        title.children.remove
      else
        title.children.remove
        text_node = Nokogiri::XML::Text.new(options[:title], doc)
        title.add_child(text_node)
      end
    end
    doc.to_html.html_safe
  end

  def is_mongoid?
    self.match(/^[a-f\d]{24}$/i) ? true : false
  end

end
