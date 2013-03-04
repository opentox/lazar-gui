$(function() {

  jQuery.fn.toggleWarnings = function(id) {
    var id = id;
    this.bind("click", function() {
      if($("a#show_model_" + id + "_warnings").html()=="show") {
        $("div#model_" + id + "_warnings").slideDown("slow");
        $("a#show_model_" + id + "_warnings").html("hide");
      }else{
        $("div#model_" + id + "_warnings").slideUp("slow");
        $("a#show_model_" + id + "_warnings").html("show");
      }
      return false;
    });
  };

  trim = function() {
    return this.replace(/^\s+|\s+$/g, '');
  }

  checkStati = function(stati) {
    stati = stati.split(", ");
    $("body")
    var newstati = new Array;
    $.each(stati, function(){
      checkProgress(this);
      if(checkStatus(this) > 0) newstati.push(this);
    });
    if (newstati.length > 0) var statusCheck = setTimeout('checkStati("' + newstati.join(", ") + '")',10000);
  };

  checkStatus = function(id) {
    if(id == "") return -1;
    var opts = {method: 'get', action: 'model/' + id + '/status', id: id};
    var status_changed = $.ajax({
      type: opts.method,
      url: opts.action,
      async: false,
      dataType: 'html',
      data: {
        '_method': 'get'
      },
      success: function(data) {
        var status_before = "";
        if ($("span#model_" + id + "_status") != null) status_before = $("span#model_" + id + "_status").html().trim();
        if (status_before == "Deleting") return -1;
        var status_after  = data.trim();
        $("span#model_" + id + "_status").animate({"opacity": "0.2"},1000);
        $("span#model_" + id + "_status").animate({"opacity": "1"},1000);
        if( status_before != status_after) {
          $("span#model_" + id + "_status").html(data);
          loadModel(id, 'model');
          if (status_after == "Completed" || status_after == "Error") id = -1;
        }
      },
      error: function(data) {
        //alert("status check error");
        id = -1;
      }
    });
    return id;
  };


  checkProgress = function(id) {
    var task = $("input#model_" + id + "_task").attr('value');
    var opts = {action: task + "/percentageCompleted" , id: id};
    var progress_changed = $.ajax({
      url: opts.action,
      async: false,
      dataType: 'html',
      data: {
        '_method': 'get'
      },
      success: function(data) {
        var progress = data.trim();
        if (progress == "100") return -1;
        $("div#model_" + id + "_progress").progressbar("value", parseInt(progress));
        $("div#model_" + id + "_progress").attr({title: parseInt(progress) + "%"});
      },
      error: function(data) {
        id = -1;
      }
    });
    return id;
  };

  loadModel = function(id, view) {
    if(id == "") return -1;
    var opts = {method: 'get', action: 'model/' + id + '/' + view, view: view };
    var out = id;
    $.ajax({
      type: opts.method,
      url: opts.action,
      dataType: 'html',
      data: {
        '_method': 'get'
      },
      success: function(data) {
        if (view == "model") $("div#model_" + id).html(data);
        if (view.match(/validation/)) $("dl#model_validation_" + id).html(data);
        addExternalLinks();
      },
      error: function(data) {
        //alert("loadModel error");
      }
    });
    return false;
  };

});

jQuery.fn.editModel = function(options) {
  var defaults = {
    method: 'get',
    action: this.attr('href'),
    trigger_on: 'click'
  };
  var opts = $.extend(defaults, options);
  this.bind(opts.trigger_on, function() {
    $.ajax({
         type: opts.method,
         url:  opts.action,
         dataType: 'html',
         data: {
           '_method': 'get'
         },
         success: function(data) {
           $("div#model_" + opts.id + "_name").html(data);
           $("input#model_" + opts.id + "_name").focus();
         },
         error: function(data) {
           alert("model edit error!");
         }
       });
    return false;
  });
};

jQuery.fn.cancelEdit = function(options) {
  var defaults = {
    method: 'get',
    action: 'model/' + options.id + '/name?mode=show',
    trigger_on: 'click'
  };
  var opts = $.extend(defaults, options);

  this.bind(opts.trigger_on, function() {
    $.ajax({
         type: opts.method,
         url:  opts.action,
         dataType: 'html',
         data: {
           '_method': 'get'
         },
         success: function(data) {
           $("div#model_" + opts.id + "_name").html(data);
         },
         error: function(data) {
           alert("model cancel error!");
         }
       });
    return false;
  });
};

jQuery.fn.saveModel = function(options) {
  var defaults = {
    method: 'put',
    action: 'model/' + options.id,
    trigger_on: 'click'
  };
  var opts = $.extend(defaults, options);

  this.bind(opts.trigger_on, function() {
    var name =  $("input#model_" + opts.id + "_name").val();
    $.ajax({
         type: opts.method,
         url:  opts.action,
         dataType: 'html',
         data: {
           '_method': 'put',
           'name': name
         },
         success: function(data) {
           $("div#model_" + opts.id + "_name").html(data);
         },
         error: function(data) {
           alert("model save error!");
         }
       });
    return false;
  });
};


jQuery.fn.deleteModel = function(type, options) {
  var defaults = {
    method: 'post',
    action: this.attr('href'),
    confirm_message: 'Are you sure?',
    trigger_on: 'click'
  };
  var opts = $.extend(defaults, options);
  this.bind(opts.trigger_on, function() {
    if(confirm(opts.confirm_message)) {
      $("div#model_" + opts.id).fadeTo("slow",0.5);
      $("span#model_" + opts.id + "_status").html("Deleting");
      $("a#delete_" + opts.id).html("");
      $.ajax({
         type: opts.method,
         url:  opts.action,
         dataType: 'html',
         data: {
           '_method': 'delete'
         },
         success: function(data) {
           $("div#model_" + opts.id).fadeTo("slow",0).slideUp("slow").remove();
         },
         error: function(data) {
           $("span#model_" + opts.id + "_status").html("Delete Error");
           //alert("model delete error!");
         }
       });
     }
     return false;
   });
};

$(document).ready(function() {
  addExternalLinks();
});

addExternalLinks = function() {
  $('A[rel="external"]').each(function() {
    $(this).attr('alt', 'Link opens in new window.');
    $(this).attr('title', 'Link opens in new window.');
    $(this).attr('target', '_blank');
  });
};
