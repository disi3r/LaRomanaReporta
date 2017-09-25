
//CODE FOR STATS WITH D3

var catJson = null;
var categoriesArray = [];
var areas = [];
var categoryGroups = [];
var chartLevel = 1;
var colorsByName = [];
var tooltip = d3.select("body")
 .append("div")
 .style("position", "absolute")
 .style("z-index", "10")
 .style("visibility", "hidden")
 .style("background", "#fff")
 .text("a simple tooltip")
 .attr("id","d3_tooltip");

function getCategoriesFilter(body_id){
  var api_call = "/api/groups?api_key=1234";
  if (body_id){
    $("#category-group-select").empty();
    api_call += "&body_id="+body_id;
  }
	$.getJSON(api_call, function (data) {
		catJson = data;
		$.each(data, function(i, item) {
			if(i!=-2){
				$("#category-group-select").append("<option value='gid_"+i+"'>"+item.group_name +"</option>");
				categoriesArray["gid_"+i] = item.categories;
				categoryGroups[item.group_name] = i;
			}
		});
	});
	$("#category-group-select").change(function() {
		// Check input( $( this ).val() ) for validity here
		var index = $( this ).val();
		if(index==-1){
			$("#category-select").addClass("hidden");
		}else{
			$("#category-select").empty();
			$("#category-select").removeClass("hidden");
			$("#category-select").append("<option value='-1'>"+"Todas las sub-categorías"+"</option>");
			$.each(categoriesArray[index], function(i, item) {
				$("#category-select").append("<option value='"+item+"'>"+item+"</option>");
			});
		}
	});
}

function getBodiesFilter(){
  $.getJSON("/api/all_areas?api_key=1234", function (all_areas) {
    areas = all_areas;
  });
	$.getJSON("/api/bodies?api_key=1234", function (data) {
		$.each(data, function(i, subdata) {
				$.each(subdata, function(z, item) {
					$("#body-select").append("<option value='"+z+"'>"+item+"</option>");
				});
		});
    $("#body-select").change(function() {
  		// Check input( $( this ).val() ) for validity here
  		var body_id = $( this ).val();
      if ( areas[body_id] ){
  			$("#area-select").empty();
  			$("#area-select").removeClass("hidden");
        $("#area-select").append('<div id="area-filter-header"/><div id="area-filter-body"/>');
        var first;
        $.each( areas[body_id], function(alabel, aoptions){
          if (!first) {
            first = 1;
            $("#area-filter-header").append('<label><input class="areas-header-option" type="radio" value="'+body_id+'-'+alabel+'" name="area-option" checked="checked"><i>'+alabel+'</i></label>');
            $("#area-filter-body").append("<select class='area-select stats_filter_select'><option value='-1'>Todas las áreas</option></select>");
            $.each(aoptions, function(ai, aname){
              $(".area-select").append("<option value='"+ai+"'>"+aname+"</option>");
            });
          }
          else {
            $("#area-filter-header").append('<label><input class="areas-header-option" type="radio" value="'+body_id+'-'+alabel+'" name="area-option"><i>'+alabel+'</i></label>');
          }
        });
        $('.areas-header-option').click(function() {
          $("#area-filter-body").empty();
          $("#area-filter-body").append("<select class='area-select'><option value='-1'>Todas las áreas</option></select>");
          var values = $(this).val().split('-');
          $.each(areas[values[0]][values[1]], function(ai, aname){
            $(".area-select").append("<option value='"+ai+"'>"+aname+"</option>");
          });
        });
  		}
      else {
        $("#area-select").addClass("hidden");
      }
      getCategoriesFilter(body_id);
	  });
  });
}

function getReportsEvolution(container_id, urlParams){
	$("#"+container_id).html('<div class="loader_throbber"><div class="three-quarters-loader"></div></div>');
	var url = "/api/reportsEvolution?api_key=1234";
	url = url + urlParams;
	$.getJSON(url, function (data) {
		$("#"+container_id).html("");
		var finalDataArray = [];
		//var parseDate = d3.time.format("%Y%m%d").parse;
		$.each(data, function(i, item) {
			var name = item.groupName;
			var color = item.color;
			var ceroArray = new Object();
			ceroArray.groupName = name;
			ceroArray.color = color;
			ceroArray.reports = Number("0");
			ceroArray.month = "0";
			//console.log(ceroArray);
			//console.log(value);
			finalDataArray.push(ceroArray);
			$.each(item.months, function(key, value) {
				value.groupName = name;
				value.color = color;
				value.reports = Number(value.reports);
				value.month = value.month.substring(0, value.month.length-3);
				//console.log(value);
				finalDataArray.push(value);
			});
		});
		data = finalDataArray;
		var cheight = $("#"+container_id).innerHeight();
		var dataGroup = d3.nest()
											.key(function(d) {return d.groupName;})
											.entries(data);
		var xmin = 80;
		var xwidth = xmin*dataGroup[0].values.length;
		var maxWidth = $("#graph-reports-evolution-chart").innerWidth()-20;
		if(maxWidth>xwidth){
			xmin = maxWidth/dataGroup[0].values.length;
			xwidth = xmin*dataGroup[0].values.length;
		}
		var svg = $('#graph-reports-evolution-chart').find('svg')[0];
		svg.innerHTML="";
		//$("#graph-reports-evolution-chart").html("");
		//var svg = d3.select("#graph-reports-evolution-chart").append("svg");
		svg.setAttribute('width', xwidth);
		svg.setAttribute('height', cheight+10);
		var vis = d3.select("#"+container_id),
				WIDTH = xwidth-50,
				HEIGHT = cheight-30,
				MARGINS = {
						top: 10,
						right: 10,
						bottom: 10,
						left: 50
				},
				lSpace = (WIDTH-MARGINS.left-MARGINS.right-20)/dataGroup[0].values.length,
				yScale = d3.scale.linear().range([HEIGHT - MARGINS.top, MARGINS.bottom]).domain([d3.min(data, function(d) {
						return d.reports;
				}), d3.max(data, function(d) {
						return d.reports;
				})]),
				yAxis = d3.svg.axis()
				.scale(yScale)
				.orient("left");
		var xScale = d3.scale.ordinal().rangeRoundBands([0 + MARGINS.left, WIDTH-MARGINS.right]);
		var xAxis = d3.svg.axis().scale(xScale).orient("bottom");
		xScale.domain(data.map(function(d) { return d.month; }));

		vis.append("svg:g")
				.attr("class", "x axis")
				.attr("transform", "translate(0," + (HEIGHT - MARGINS.bottom) + ")")
				.call(xAxis);
		vis.append("svg:g")
				.attr("class", "y axis")
				.attr("transform", "translate(" + (MARGINS.left) + ",0)")
				.call(yAxis);

		var lineGen = d3.svg.line()
				.x(function(d) {
						return xScale(d.month);
				})
				.y(function(d) {
						return yScale(d.reports);
				})
				.interpolate("basis");
				$("#categories-list-evolution").html("");
		dataGroup.forEach(function(d,i) {
				//console.log(d);
				//console.log(i);
				var newKey = d.key.replace(/\ /g, '_');
				vis.append('svg:path')
				.attr('d', lineGen(d.values))
				.attr('stroke-width', 2)
				.attr('id', 'line_'+newKey)
				.attr('fill', 'none')
				.attr('stroke', getRandomColor(d.values[0].color,d.values[0].groupName))
				.style('cursor', 'pointer')
				.on("mouseover", function(){
					tooltip.text(d.values[0].groupName);
					return tooltip.style("visibility", "visible");
				})
				.on("mousemove", function(){
					return tooltip.style("top", (d3.event.pageY-10)+"px").style("left",(d3.event.pageX+10)+"px");
				})
				.on("mouseout", function(){
					return tooltip.style("visibility", "hidden");
				})
				.on('click', function(){
						tooltip.style("visibility", "hidden");
						setCategoryGroupFilter(d.values[0].groupName);
				 });
				$("#categories-list-evolution").append("<li id='ev_catref_"+newKey+"'></li>");
				$("#ev_catref_"+newKey).css("color",  getRandomColor(d.values[0].color,d.values[0].groupName));
				$("#ev_catref_"+newKey).addClass("legend");
				$("#ev_catref_"+newKey).on('click',function(){
										var active   = d.active ? false : true;
										var opacity = active ? 0 : 1;
										d3.select("#line_" + newKey).style("opacity", opacity);
										d.active = active;
										/*tooltip.style("visibility", "hidden");
										setCategoryGroupFilter(d.values[0].groupName);*/
								});
				$("#ev_catref_"+newKey).text(d.key);
				/*vis.append("text")
						.attr("x", (lSpace)+i*lSpace)
						.attr("y", HEIGHT)
						.style("fill", "black")
						.attr("class","legend")
						.on('click',function(){
								var active   = d.active ? false : true;
								var opacity = active ? 0 : 1;
								d3.select("#line_" + d.key).style("opacity", opacity);
								d.active = active;
						})
						.text(d.key);*/
		});
		var xLabels = $(".x.axis .tick text");
		$.each(xLabels, function(key, value) {
			value.setAttribute('x', -(xmin/2));
			value.setAttribute('y', 10);
		});

	});
}

function getReportsPerCategoriesChart(container_id,urlParams){
	$("#"+container_id).html('<div class="loader_throbber"><div class="three-quarters-loader"></div></div>');
	var url = "/api/reportsByCategoryGroup?api_key=1234";
	url = url + urlParams;
	d3.json(url, function(data) {
		$("#categories-list").html("");
		$("#"+container_id).html('');

		var width = $("#"+container_id).innerWidth()*0.79,
				height = $("#"+container_id).innerHeight(),
				radius = Math.min(width, height) / 2;

		var arc = d3.svg.arc()
				.outerRadius(radius - 10)
				.innerRadius(radius - 70);

		var pie = d3.layout.pie()
				.sort(null)
				.value(function(d) { return d.reports; });

		var svg = d3.select("#"+container_id).append("svg")
				.attr("width", width)
				.attr("height", height)
			.append("g")
				.attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

		$.each(data, function(i, item) {
			$("#categories-list").append('<li style="cursor: pointer;" onclick="setCategoryGroupFilter(\''+item.groupName+'\');"><div class="circulo" style="background-color: '+getRandomColor(item.color,item.groupName)+';"></div><span style="color: '+getRandomColor(item.color,item.groupName)+';">'+item.groupName+'</span></li>');
		});

		var g = svg.selectAll(".arc")
				.data(pie(data))
			.enter().append("g")
				.attr("class", "arc");

		g.append("path")
				.attr("d", arc)
				.style("fill", function(d) {
					return getRandomColor(d.data.color,d.data.groupName); })
				.style('cursor', 'pointer')
				.on("mouseover", function(d){tooltip.html("<b>"+d.data.groupName + "</b><br/>" + d.data.reports); return tooltip.style("visibility", "visible");})
				.on("mousemove", function(){return tooltip.style("top", (d3.event.pageY-10)+"px").style("left",(d3.event.pageX+10)+"px");})
				.on("mouseout", function(){return tooltip.style("visibility", "hidden");})
				.on('click', function(d){
						tooltip.style("visibility", "hidden");
						setCategoryGroupFilter(d.data.groupName);
				 });

		g.append("text")
				.attr("transform", function(d) { return "translate(" + arc.centroid(d) + ")"; })
				.attr("dy", ".35em")
				.style("display","none")
				.text(function(d) { return d.data.groupName; })


	});

	function type(d) {
		d.reports = +d.reports;
		return d;
	}
}

function setCategoryGroupFilter(groupName){
	var id = getIdFromCategoryGroup(groupName);
	if(id){
		$("#category-group-select option[value='gid_"+id+"']").attr('selected', 'selected');
		$("#category-group-select").change();
		$("#category-select option[value='-1']").attr('selected', 'selected');
		//chartLevel=2; //ESTOY DESGLOSANDO UN GRUPO
		getCharts();
	}else{
		//NO ES UN GRUPO, ENTONCES ES UNA categoría
		var categoryName = groupName;
		id = getGroupIdFromCategory(categoryName);
		if(id){
			$("#category-group-select option[value='gid_"+id+"']").attr('selected', 'selected');
			$("#category-group-select").change();
			$("#category-select option[value='"+categoryName+"']").attr('selected', 'selected');
			//chartLevel=3; //ESTOY DESGLOSANDO UNA CATEGORÍA
			getCharts();
		}
	}
	return false;
}

function getGroupIdFromCategory(categoryName){
		var id = false;
		$.each(catJson.categories, function(i, item) {
			if(!id){
				$.each(item.categories, function(z,category) {
					var cat = new String(category.trim());
					var cat2 = new String(categoryName.trim());
					if(cat.valueOf() == cat2.valueOf()){
						id = i;
					}
				});
			}
		});
	return id;
}

function getIdFromCategoryGroup(groupName){
		if(categoryGroups[groupName]){
			return categoryGroups[groupName];
		}
	return false;
}

function getReportsByStateChart(urlParams){
	$("#graph-reports-by-state-table").html('<tbody><tr><td><div class="loader_throbber"><div class="three-quarters-loader"></div></div></td></tr></tbody>');
	var url = "/api/reportsByState?api_key=1234";
	url = url + urlParams;
	$.getJSON(url, function (data) {

		statesTable = "<tbody>";
		nextRowColor = null;
		$.each(data, function(i, item) {
			statesTable = statesTable + "<tr><td class='report-state-count'>"+item.reports+"</td><td class='report-state'>"+item.state+"</td></tr>";
		});
		statesTable = statesTable + "</tbody>";
		$("#graph-reports-by-state-table").html(statesTable);
	});
}

function getAnswerTimeByStateChart(urlParams){
	var url = "/api/answerTimeByState?api_key=1234";
	url = url + urlParams;
	$.getJSON(url, function (data) {
		statesTable = "<tbody>";
		nextRowColor = null;
		totalDays = 0;
		count=0;
		$.each(data, function(i, item) {
			statesTable = statesTable + "<tr><td class='report-state-count'>"+item.averageTime+"</td><td class='report-state'>"+item.state+"</td></tr>";
			totalDays += item.averageTime;
			count += 1;
		});
		average = totalDays/count;
		average = Math.round(average * 100) / 100; //Redondeo en 2 decimales
		//$("#averageDays").html("<span class='average-days'>"+average+"</span><span class='states-time-chart'>Días promedio</span>");
		statesTable = statesTable + "</tbody>";
		$("#graph-average-answertime-table").html(statesTable);
	});
}

function getTotalsChart(urlParams){
	var url = "/api/getTotals?api_key=1234";
	url = url + urlParams;

	$.getJSON(url, function (data) {
		$("#graph-total-users-value").html(data.users);
		$("#graph-total-reports-value").html(data.reports);
	});
}

function getAnswerTimeByCategoryChart(container_id,urlParams){
			$("#"+container_id).html("");
			var w = $("#"+container_id).innerWidth()*0.79,
					h = 200;
			var svg = d3.select("#"+container_id).append("svg")
				.attr("width", w)
				.attr("height", h);

			var url = "/api/answerTimeByCategoryGroup?api_key=1234";
			url = url + urlParams;

			d3.json(url, function(json) {

				var data = json;

				var max_n = 0;
				for (var d in data) {
					max_n = Math.max(data[d].averageTime, max_n);
				}

				var dx = w / max_n;
				var dy = 25;

				// bars
				var bars = svg.selectAll(".bar")
					.data(data)
					.enter()
					.append("rect")
					.attr("class", function(d, i) {return "bar " + d.groupName;})
					.attr("x", function(d, i) {return 0;})
					.attr("y", function(d, i) {return (dy*i)+(5*i);})
					.attr("width", function(d, i) {return dx*d.averageTime})
					.attr("height", dy)
					.style("fill", function(d,i) {
					return getRandomColor(d.color,d.groupName); })
					.style("margin-bottom", "10px")
					.style('cursor', 'pointer')
					.on("mouseover", function(d){
						tooltip.text(d.groupName);
						return tooltip.style("visibility", "visible");
					})
					.on("mousemove", function(){
						return tooltip.style("top", (d3.event.pageY-10)+"px").style("left",(d3.event.pageX+10)+"px");
					})
					.on("mouseout", function(){
						return tooltip.style("visibility", "hidden");
					})
					.on('click', function(d){
							tooltip.style("visibility", "hidden");
							setCategoryGroupFilter(d.groupName);
					 });

				// labels
				var text = svg.selectAll("text")
					.data(data)
					.enter()
					.append("text")
					.attr("class", function(d, i) {return "label " + d.groupName;})
					.attr("x", 5)
					.attr("y", function(d, i) {return dy*i + 15 + (5*i);})
					.text( function(d) {return d.groupName + " (" + d.averageTime  + " días)";})
					.attr("font-size", "15px")
					.style("font-weight", "bold")
					.style('cursor', 'pointer')
					.on("mouseover", function(d){
						tooltip.text(d.groupName);
						return tooltip.style("visibility", "visible");
					})
					.on("mousemove", function(){
						return tooltip.style("top", (d3.event.pageY-10)+"px").style("left",(d3.event.pageX+10)+"px");
					})
					.on("mouseout", function(){
						return tooltip.style("visibility", "hidden");
					})
					.on('click', function(d){
							tooltip.style("visibility", "hidden");
							setCategoryGroupFilter(d.groupName);
					 });
			});
}

function getApiRequestURLParams(){
	var date_from = $("#stats-start-date").val();
	var date_to = $("#stats-end-date").val();
	$("#select-period-title").attr('class', 'hidden');
	/*$("#select-period-title").toggleClass("hidden");*/
	$("#date_from").html(date_from);
	$("#date_to").html(date_to);
	if(date_from==""){
		$("#date_from").html("el comienzo");
	}
	if(date_to==""){
		$("#date_to").html("hoy");
	}
	if($( "#chart-container" ).hasClass( "hidden" )){
			$("#chart-container").toggleClass("hidden");
	}
	date_from = date_from.replace(/\//g, "-");
	date_to = date_to.replace(/\//g, "-");
	var categoryGroup = $("#category-group-select").val();
	var category = $("#category-select").val();
  var area = $(".area-select").val();
	if(categoryGroup==-1){
		chartLevel=1; //NO FILTRO NI GRUPOS NI CATEGORÍAS
		categoryGroup=null;
		category=null;
	}else{
		chartLevel = 3; //FILTRO POR CATEGORIA
		categoryGroup = categoryGroup.replace("gid_", "");
		if(category==-1){
			chartLevel = 2; //FILTRO Y DESGLOSO POR GRUPO
			category=null;
		}
	}
	var load = 1 //1= CACHE ON; 0= CACHE FALSE;
	var body = $("#body-select").val();
	if(body==-1){
		body = null;
	}
	var url = "";
	if(date_from){
		url += "&from="+date_from;
	}
	if(date_to){
		url += "&to="+date_to;
	}
	if(categoryGroup){
		url += "&gid="+categoryGroup;
	}
	if(category){
		url += "&category="+category;
	}
  if(area && area!=-1){
    url += "&area="+area;
  }
	if(load){
		url += "&load="+load;
	}
	if(body){
		url += "&body_id="+body;
	}
	return url;
}

function getCharts(){
	var urlParams = getApiRequestURLParams();
	getTotalsChart(urlParams);
	getReportsByStateChart(urlParams);
	getReportsPerCategoriesChart("graph-reports-categories",urlParams);
	getReportsEvolution("graph-reports-evolution-chart-visualisation",urlParams);
	getAnswerTimeByStateChart(urlParams);
	getAnswerTimeByCategoryChart("graph-average-answertime-by-category-chart",urlParams);
}

function getRandomColor(originalColor,groupName){
		if(chartLevel==1 && originalColor){
			return originalColor;
		}
		var letters = '0123456789ABCDEF';
		var color = '#';
		for (var i = 0; i < 6; i++ ) {
				color += letters[Math.floor(Math.random() * 16)];
		}
		if((chartLevel==1 && !originalColor) || chartLevel==2 || chartLevel==3){
			if(colorsByName[groupName]){
				return colorsByName[groupName];
			}else{
				colorsByName[groupName] = color;
			}
		}
		return color;
}

function download_totals(){
	var url = "/api/getTotals?api_key=1234&format=csv";
	url = url + getApiRequestURLParams();
	var win = window.open(url, '_blank');
}

function download_reports(){
	var url = "/api/reports?api_key=1234&format=csv";
	url = url + getApiRequestURLParams();
	var win = window.open(url, '_blank');
}

$( document ).ready(function() {
});
