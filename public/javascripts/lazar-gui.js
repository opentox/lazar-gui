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

remaining = function(id,tasktime,type,compoundsSize) {
  var est = document.getElementById("est_"+id);
  var now = new Date().getTime();
  if ( type == "true" ){
    var approximate = new Date(tasktime*1000 + compoundsSize*100*(id+1));
  } else {
    var approximate = new Date(tasktime*1000 + compoundsSize*1000*(id+1));
  }
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

renderTask = function(task_uri,model_id,id) {
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
