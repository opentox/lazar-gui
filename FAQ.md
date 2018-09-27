## *lazar* Frequently Asked Questions

### I find multiple entries with different values for the same compound in the list of neighbors. Where do they come from and what is their impact on the prediction?

Multiple entries for the same structure originate from different biological
experiments. `lazar` can use the information from multiple experiments to
improve predictions, by considering each measurement as a separate example.
This has the effect, that the impact of a neighbor on the prediction is
increased, if repeated measurements give the same (classification) or very
similar (regression) values, and decreased if the measurements differ a lot.

### I get different values, if I repeat a prediction for the same compound and endpoint. Why?

This may happen for regression predictions only. `lazar` uses the random forest
algorithm from R's Caret package to build local QSAR models. This algorithm
uses *random* internal training set splits for parameter optimisations. This
randomness can lead to models with slightly different parameters (and thus
predictions) for the same set of neighbors. 

### The *lazar* program's interface has changed, and I am not sure how to use the information given with regard to its confidence. In the former version I would consider a confidence value higher than 0.025 as reliable, but now there is no such parameter in the prediction results. 

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

### How can I use *lazar* locally on my computer

If you are familiar with docker, you can use one of our docker images to run lazar locally:

<https://hub.docker.com/r/insilicotox/lazar>

<https://hub.docker.com/r/insilicotox/nano-lazar>

If you want to install lazar/nano-lazar without docker you should know how to use UNIX/Linux and the Ruby programming language. Source code and brief installation instructions for the GUIs is available at:

<https://github.com/opentox/lazar-gui>

<https://github.com/opentox/nano-lazar>

You can also use just the libraries from the command line:

<https://github.com/opentox/lazar

Documentation is available at:

<http://www.rubydoc.info/gems/lazar>

lazar depends on a couple of external libraries and programs, that could be difficult to install. Due to limited resources we cannot provide support, please use the docker version if you cannot manage it on your own.
