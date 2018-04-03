## *lazar* Frequently Asked Questions

#### The *lazar* program's interface has changed, and I am not sure how to use the information given with regard to its confidence. In the former version, I would consider a confidence value higher than 0.025 as reliable. But now, there is no such parameter in the prediction results. How can I consider a prediction as presenting high or low confidence?

In the past many users had problems to interpret the confidence level,
for this reason we provide now the probabilities that the prediction
belongs to one of the two classes. In contrast to the confidence level,
these numbers can be interpreted as real probabilities ranging from 0 to
1.

Reliable prediction have a high probability for the predicted class and
a low probability for the other one. Unreliable predictions have similar
values for both classes, and are caused by a lot of contradictory
activities of similar compounds.

Probabilities are calculated from the activities and similarities of
neighbors, please make sure to inspect the neighbors list for any
inconsistencies that might affect the prediction.

#### How can I use *lazar* locally on my computer
If you are familiar with docker, you can use one of our docker images to run lazar locally:
https://hub.docker.com/r/insilicotox/lazar
https://hub.docker.com/r/insilicotox/nano-lazar

If you want to install lazar/nano-lazar without docker you should know how to use UNIX/Linux and the Ruby programming language. Source code and brief installation instructions for the GUIs is available at:

https://github.com/opentox/lazar-gui
https://github.com/opentox/nano-lazar

You can also use just the libraries from the command line:

https://github.com/opentox/lazar

Documentation is available at:

http://www.rubydoc.info/gems/lazar

lazar depends on a couple of external libraries and programs, that could be difficult to install. Due to limited resources we cannot provide support, please use the docker version if you cannot manage it on your own.
