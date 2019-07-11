$(document).ready(function() {
  addExternalLinks();
  popOver();
});

addExternalLinks = function() {
  $('A[rel="external"]').each(function() {
    $(this).attr('alt', 'Link opens in new window.');
    $(this).attr('title', 'Link opens in new window.');
    $(this).attr('target', '_blank');
  });
};

popOver = function(){
  $('[data-toggle="popover"]').popover();
  $('.modal').on('hidden.bs.modal', function () {
    $(this).removeData('bs.modal');
  });
  $('.modal').on('show.bs.modal', function(e){
    var button = $(e.relatedTarget);
    var modal = $(this);
    modal.find('.modal-content').load(button.data("remote"));
  });
};

var HttpClient = function() {
  this.get = function(aUrl, aCallback) {
  var anHttpRequest = new XMLHttpRequest();
  anHttpRequest.onreadystatechange = function() {
  if (anHttpRequest.readyState == 4 && anHttpRequest.status == 200)
    aCallback(anHttpRequest.responseText);
  }
    anHttpRequest.open( "GET", aUrl, true );
    anHttpRequest.send( null );
  }
};  

// functions used in predict.haml

// GET request
/*$(function() {
  $('a[data-toggle="tab"]').on('click', function (e) {
    localStorage.setItem('lastTab', $(e.target).attr('href'));
  });
  var lastTab = localStorage.getItem('lastTab');
  if (lastTab) {
    $('a[href="'+lastTab+'"]').click();
  }
});*/

// get and check input
function getInput(){
  identifier = document.getElementById("identifier").value.trim();
  fileselect = document.getElementById("fileselect").value;
  if (fileselect != ""){
    return 1;
  };
  if (identifier != ""){
    return 2;
  };
  return 0;
};

// display wait animation after click on predict button
// check form fields, input file or SMILES, endpoint selection
function showcircle() {
  switch (getInput()){
    case 0:
      alert("Please draw or insert a chemical structure.");
      return false;
      break;
    case 1:
      if (checkfile() && checkboxes()){
        button = document.getElementById("submit");
        image = document.getElementById("circle");
        button.parentNode.replaceChild(image, button);
        $("img.circle").show();
        return true;
      };
      return false;
      break;
    case 2:
      if (checksmiles() && checkboxes()){
        button = document.getElementById("submit");
        image = document.getElementById("circle");
        button.parentNode.replaceChild(image, button);
        $("img.circle").show();
        return true;
      };
      return false;
      break;
    default: false;
  };
  return false;
};

// check if a file was selected for upload
function checkfile() {
  var fileinput = document.getElementById("fileselect");
  if(fileinput.value != "") {
    return true;
  };
  alert("Please select a file (csv).");
  return false;
};

// check if a smiles string was entered
function checksmiles () {
  getsmiles();
  if (document.form.identifier.value == "") {
    alert("Please draw or insert a chemical structure.");
    document.form.identifier.focus();
    $("img.circle").hide();
    return false;
  };
  return true;
};

// check if an endpoint was selected
function checkboxes () {
  var checked = false;
  $('input[type="checkbox"]').each(function() {
    if ($(this).is(":checked")) {
      checked = true;
    };
  });
  if (checked == false){
    alert("Please select an endpoint.");
    $("img.circle").hide();
    return false;
  };
  return true;
};

// display jsme editor with option
function jsmeOnLoad() {
  jsmeApplet = new JSApplet.JSME("appletContainer", "380px", "340px", {
    //optional parameters
    "options" : "polarnitro"
  });
document.JME = jsmeApplet;
};

// get and take smiles from jsme editor for input field
function getsmiles() {
  if (document.JME.smiles() != '') {
    document.form.identifier.value = document.JME.smiles() ;
  };
};

// show model details
function loadDetails(id, model_url) {
  button = document.getElementById("link"+id);
  span = button.childNodes[1];
  if (span.className == "fa fa-caret-right"){
    span.className = "fa fa-caret-down";
  } else if (span.className = "fa fa-caret-down"){
    span.className = "fa fa-caret-right";
  };
  image = document.getElementById("circle"+id);
  if ($('modeldetails'+id).length == 0) {
    $(button).hide();
    $(image).show();
    aClient = new HttpClient();
    aClient.get(model_url, function(response) {
      var details = document.createElement("modeldetails"+id);
      details.innerHTML = response;
      document.getElementById("details"+id).appendChild(details);
      $(button).show();
      $(image).hide();
      addExternalLinks();
    });
  }
}


// functions used in batch.haml

var markers = [];

progress = function(value,id) {
  var percent = Math.round(value);
  var bar = document.getElementById("bar_"+id);
  var est = document.getElementById("est_"+id);
  var prog = document.getElementById("progress_"+id);
  bar.style.width = value + '%';
  if (percent == 100){
    prog.style.display = "none";
    est.style.display = "none";
  };
};

remaining = function(id,approximate) {
  var est = document.getElementById("est_"+id);
  var now = new Date().getTime();
  var remain = approximate - now;
  var minutes = Math.floor((remain % (1000 * 60 * 60)) / (1000 * 60));
  var seconds = Math.floor((remain % (1000 * 60)) / 1000);
  if ( minutes <= 0 && seconds <= 0 ) {
    var newtime = "0m " + "00s ";
  } else {
    var newtime = minutes + "m " + seconds + "s ";
  }
  est.innerHTML = newtime;
};

renderTask = function(task_uri,id) {
  var uri = task_uri;
  var aClient = new HttpClient();
  aClient.get(uri, function(res) {
    var response = JSON.parse(res);
    progress(response['percent'],id);
    if (response['percent'] == 100){
      window.clearInterval(markers[id]);
      $("a#downbutton_"+id).removeClass("disabled");
      $("a#detailsbutton_"+id).removeClass("disabled");
      $("a#downbutton_"+id).removeClass("btn-outline-info");
      $("a#detailsbutton_"+id).removeClass("btn-outline-info");
      $("a#downbutton_"+id).addClass("btn-info");
      $("a#detailsbutton_"+id).addClass("btn-info");
    };
  });
};

simpleTemplating = function(data) {
  var html = '<ul class=pagination>';
  $.each(data, function(index, item){
    html += '<li>'+ item +'</li>'+'</br>';
  });
  html += '</ul>';
  return html;
};

pagePredictions = function(task_uri,model_id,id,compoundsSize){
  button = document.getElementById("detailsbutton_"+id);
  span = button.childNodes[1];
  if (span.className == "fa fa-caret-right"){
    span.className = "fa fa-caret-down";
    $('#data-container_'+id).removeClass("d-none");
    $('#data-container_'+id).show();
    $('#pager_'+id).show();
    $('#pager_'+id).pagination({
      dataSource: task_uri,
      locator: 'prediction',
      totalNumber: compoundsSize,
      pageSize: 1,
      showPageNumbers: true,
      showGoInput: true,
      formatGoInput: 'go to <%= input %>',
      formatAjaxError: function(jqXHR, textStatus, errorThrown) {
        $('#data-container_'+id).html(errorThrown);
      },
      /*ajax: {
        beforeSend: function() {
          $('#data-container_'+id).html('Loading content ...');
        }
      },*/
      callback: function(data, pagination) {
        var html = simpleTemplating(data);
        $('#data-container_'+id).html(html);
        //$('#data-container_'+id).css("min-height", $(window).height() + "px" );
      }
    });
  } else if (span.className = "fa fa-caret-down"){
    span.className = "fa fa-caret-right";
    $('#data-container_'+id).hide();
    $('#pager_'+id).hide();
  };
};
