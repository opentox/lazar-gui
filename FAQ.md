## lazar Frequently Asked Questions

####The LAZAR program's interface has changed, and I am not sure how to use the information given with regard to its confidence. In the former version, I would consider a confidence value higher than 0.025 as reliable. But now, there is no such parameter in the prediction results. How can I consider a prediction as presenting high or low confidence?

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
