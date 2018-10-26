require 'minitest/autorun'
require 'rest-client'
require 'nokogiri'
require '~/lazar/lib/lazar.rb'
$models = OpenTox::Model::Validation.all
$r_model = $models.select{|m| m if m.model.name == "LOAEL (training_log10)"}[0].id.to_s
$c_model = $models.select{|m| m if m.model.name == "Mutagenicity (kazius)"}[0].id.to_s

class WebServiceTests < Minitest::Test

  def test_prediction

    # regression
    response = RestClient.post "http://localhost:8088/predict", {identifier: "O=[N+]([O-])c1ccccc1", selection: {$r_model=>""}}
    xml = Nokogiri::HTML.parse(response.body)
    value = xml.css('td')[1].css('p')[2].text.split[1].to_f
    assert value.between?(0.06,0.09)

    # classification
    response = RestClient.post "http://localhost:8088/predict", {identifier: "O=[N+]([O-])c1ccccc1", selection: {$c_model=>""}}
    xml = Nokogiri::HTML.parse(response.body)
    value = xml.css('td')[1].css('p')[4].text.split.last
    assert_equal "mutagenic", value
  end

  def test_validation

		# regression
    response = RestClient.get "http://localhost:8088/predict/modeldetails/#{$r_model}"
    xml = Nokogiri::HTML.parse(response.body)
    links = xml.css('a')
    assert_equal "Algorithm::Caret.rf", links[3].children.text.strip

		# classification
    response = RestClient.get "http://localhost:8088/predict/modeldetails/#{$c_model}"
    xml = Nokogiri::HTML.parse(response.body)
    links = xml.css('a')
    assert_equal "Algorithm::Classification.weighted_majority_vote", links[3].children.text.strip
  end

end
