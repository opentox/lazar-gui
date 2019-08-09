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

  def remove_task_data(pid)
    task = Task.find_by(:pid => pid)
    if task and !task.subTasks.blank?
      task.subTasks.each_with_index do |task_id,idx|
        t = Task.find task_id
        predictionDataset = Dataset.find t.dataset_id if t.dataset_id
        if predictionDataset && idx == 0
          trainingDataset = Dataset.find predictionDataset.source
          predictionDataset.delete
          # delete training dataset unless it is one used for prediction models
          models = Model::Validation.all
          training_datasets = models.collect{|m| m.training_dataset.id.to_s}
          trainingDataset.delete unless training_datasets.include?(trainingDataset.id.to_s)
        elsif predictionDataset
          predictionDataset.delete
        end
        t.delete
      end
    end
    task.delete if task
  end

end
