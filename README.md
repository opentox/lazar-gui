*lazar* GUI
===========
  lazar ( Lazy Structure- Activity Relationships ) takes a chemical structure as input and provides predictions for a variety of toxic properties. lazar uses an automated and reproducible read across procedure to calculate predictions. Rationales for predictions, applicability domain estimations and validation results are presented in a clear graphical interface for the critical examination by toxicological experts.

Installation:
-------------

```
bundle install
```

Service start:
--------------

```
sudo mongod &
R CMD Rserve --vanilla &
unicorn -p 8088 -c unicorn.rb -E production
```

Visit:
------

```
http://localhost:8088
```

