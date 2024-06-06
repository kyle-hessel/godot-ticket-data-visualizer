extends Control
class_name ae_dash

@onready var ae_data := preload("res://data/AE_Data_04_23_24.csv") # temporary, later this will be loaded in through a FileDialog

signal data_parsed

#region global variable declarations
@export var color_array: Array[Color]

const FULL_DAY: float = 24
const HOUR_OFFSET: float = 7
const ROUNDING_PLACE: int = 3
const ARC_BASE_RADIUS: int = 150
const ARC_WIDTH: int = 250
const ARC_POINT_COUNT: int = 40
const DEFAULT_DATE_RANGE: Dictionary = {"Start": [0, 0, 0], "End": [0, 0, 0]}

@onready var pie_chart_center

# these four dictionaries get routinely flushed as data is processed - unreliable outside of the respective functions that use them already.
var turnaround_time_sums: Dictionary
var closed_total: Dictionary
var in_prog_total: Dictionary
var on_hold_total: Dictionary

var last_angle: float = 0.0
var first_draw: bool = true
var alternate_spacing: bool = false

enum CHART_TYPE {
	PIE_CHART = 0,
	BAR_CHART = 1,
	PLOT_CHART = 2,
	HEAT_CHART = 3
}

# this value is cached from the value for the entire team in closed_total before that gets flushed.
var closed_total_in_dataset: int
var category_percentages: Dictionary
var technician_percentages: Dictionary
#endregion

func _ready() -> void:
	randomize()
	pie_chart_center = get_viewport_rect().size / 2
	#pie_chart_center.x += 100
	$ChartTitle.position.x = pie_chart_center.x - 110
	
	data_parsed.connect(_on_data_parsed)
	
	parse_csv_data(ae_data.records)

#region Graph visualization
func _on_data_parsed() -> void:
	queue_redraw() # calls _draw

func _draw() -> void:
	if !first_draw:
		create_chart(category_percentages, "Tickets by category", CHART_TYPE.PIE_CHART)
		#create_chart(technician_percentages, "Tickets by technician", CHART_TYPE.PIE_CHART)
	first_draw = false

func create_chart(dataset: Dictionary, title: String, chart_type: CHART_TYPE = CHART_TYPE.PIE_CHART) -> void:
	$ChartTitle.text = title
	
	match chart_type:
		CHART_TYPE.PIE_CHART:
			draw_circle(pie_chart_center, ARC_BASE_RADIUS * 1.5, Color.FLORAL_WHITE)
			# sort category values.
			var data_sort: Array = dataset.values()
			# NOTE: use category_percentages.find_key(data_sort[i]) to retrieve the names again later for pie-chart labeling.
			data_sort.sort()
			
			var dataset_clone: Dictionary = dataset.duplicate()
			var perc_total: float
			
			for data_perc: float in data_sort:
				var label: String = dataset_clone.find_key(data_perc)
				dataset_clone.erase(label) # erase the key in the duplicate dataset to avoid duplicate titles if two keys have the same value. happened during testing!
				var clr: Color = color_array.pick_random() # NOTE: This will crash if there aren't enough colors to be supplied relative to how many pieces of data there are to visualize.
				plot_data(data_perc, label, clr, chart_type)
				color_array.erase(clr) # prevent colors from being reused
				perc_total += data_perc # sum all the percentages to calculate Other at the end
			
			var perc_remainder: float = round_to_dec(100.0 - perc_total, 2)
			last_angle -= 1 # hacky fix
			plot_data(perc_remainder, "Other", Color.FLORAL_WHITE, chart_type)
			
		CHART_TYPE.BAR_CHART:
			pass
		_:
			pass

func plot_data(perc: float, label: String, clr: Color, chart_type: CHART_TYPE = CHART_TYPE.PIE_CHART) -> void:
	match chart_type:
		CHART_TYPE.PIE_CHART:
			# convert the percentage value to degrees for a pie chart
			var angle: float = round_to_dec(perc * 3.6, ROUNDING_PLACE)
			var new_angle: float = last_angle + angle + 1
			
			# draw an arc using this information (a piece of the pie chart)
			draw_arc(pie_chart_center, ARC_BASE_RADIUS, deg_to_rad(last_angle), deg_to_rad(new_angle), ARC_POINT_COUNT, clr, ARC_WIDTH, true)
			
			# find angle right in the middle of this piece of the pie chart for label creation
			var mid_angle: float = new_angle - ((new_angle - last_angle) / 2) - 3
			last_angle += angle # cache angle for starting the next arc
			
			# derive a unit vector from the calculated mid angle
			var text_dir: Vector2 = Vector2.from_angle(deg_to_rad(mid_angle))
			
			# alternate the last multiplier every time this runs to make the pie chart more legible.
			var distance_modifier: float
			if alternate_spacing:
				distance_modifier = 1.2
			else:
				distance_modifier = 1.3
			alternate_spacing = !alternate_spacing
			
			# make a new vector starting at the pie chart center and moving to the edge of the circle using a scaled version of the unit vector.
			var text_vector: Vector2 = pie_chart_center + (text_dir * ARC_WIDTH * distance_modifier)
			
			
			# create a label for this piece of the chart.
			var pie_label: Label = Label.new()
			
			# modify titles if needed
			match label:
				"password reset":
					label = "account issue"
			
			label += " (" + str(perc) + "%)"
			pie_label.text = label.capitalize()
			$TextHolder.add_child(pie_label)
			
			# manually adjust the label's x pos if it's on the left side of the pie chart, since godot doesn't support setting layout mode through code.
			# FIXME: this may need more tweaking later.
			if mid_angle > 110 && mid_angle < 245:
				if label.length() > 15:
					text_vector.x -= 160
				elif label.length() > 10:
					text_vector.x -= 100
				else:
					text_vector.x -= 50 
			
			# set the label's position
			pie_label.position = text_vector
			
		CHART_TYPE.BAR_CHART:
			pass
		_:
			pass
#endregion

#region Data processing
func parse_csv_data(ae_records: Array) -> void:
	var date_range: Dictionary = {"Start": [2024, 3, 18], "End": [0, 0, 0]}
	var technician: String = "Help Desk"
	
	# output data for the entire dataset with pure defaults
	#fetch_data_by_category(ae_records)
	
	# fetch data for all categories within a date range
	fetch_data_by_category(ae_records, [""], date_range, technician)
	
	if technician == "Help Desk":
		get_technician_percentages() # NOTE : Order matters here, technician_percentages will be populated by whatever the last category was.
	
	# cache the overall closed total before moving onto categories.
	closed_total_in_dataset = closed_total[technician]
	
	#output data for specific categories of ticket
	var categories_to_query: Array[Array] = [
		["password reset", "account", "ellucian"],
		["zoom"],
		["email", "outlook"],
		["teams"],
		["duo"],
		["canvas"],
		["print"],
		["laptop"],
		["mifi", "mi-fi"],
		["adobe", "creative cloud"],
	]
	
	# iterate over every included category.
	for cat_pos: int in categories_to_query.size():
		var cat: Array = categories_to_query[cat_pos]
		fetch_data_by_category(ae_records, cat, date_range, technician)
	
	#print(category_percentages)
	emit_signal("data_parsed")

func fetch_data_by_category(ae_records: Array, category: Array = [""], time_range: Dictionary = DEFAULT_DATE_RANGE, technician: String = "Help Desk") -> void:
	# flush the dictionaries. this is inefficient compared to just collecting multiple data types in the same
	# for-loop, but is simpler and this application isn't really performance critical. if it doesn't scale up
	# well, then I can redesign both sum_ticket_count and sum_turnaround_times to optimize.
	flush_dictionaries()
	
	# if the Start and End values of time_range are at their defaults, computing the range isn't necessary.
	var compute_range: bool = true
	if time_range["Start"][0] == 0 && time_range["End"][0] == 0:
		compute_range = false
	
	# get ticket count and a sum of turnaround times for the given dataset.
	for record: Dictionary in ae_records:
		#FIXME: Try and make this code (and its repeat farther down) into a reusable function despite the multiple return values needed.
		# Should work on caching and reusing the realigned time and date values, too.
		#region somewhat redundant, reused code
		# obtain sub-strings from 'Originated Date' and 'Completed Date' fields that contain just what we need.
		var created_date: String = record["Originated Date"].left(10)
		var created_time: String = record["Originated Date"].right(9).substr(0, 5)
		#var completed_date: String = record["Completed Date"].left(10)
		#var completed_time: String = record["Completed Date"].right(9).substr(0, 5)
		
		# split the strings into arrays of floats, so that we can work with the numeric data.
		var created_date_data: PackedFloat64Array = created_date.split_floats("-")
		#var completed_date_data: PackedFloat64Array = completed_date.split_floats("-")
		var created_time_data: PackedFloat64Array = created_time.split_floats(":")
		#var completed_time_data: PackedFloat64Array = completed_time.split_floats(":")
		
		var turnaround_time_to_minutes: float
		
		# only parse data if all fields are filled out.
		# the below should always be true, so this check is redundant.
		#if created_date_data.size() == 3: #&& completed_date_data.size() == 3:
		
		# offset times by seven hours as the data is misaligned.
		var offset_created_data: Array[PackedFloat64Array] = offset_date_and_time(created_date_data, created_time_data, HOUR_OFFSET)
		#var offset_completed_data: Array[PackedFloat64Array] = offset_date_and_time(completed_date_data, completed_time_data, HOUR_OFFSET)
		
		# assign the adjusted values back to the existing variables.
		created_date_data = offset_created_data[0]
		created_time_data = offset_created_data[1]
		#completed_date_data = offset_completed_data[0]
		#completed_time_data = offset_completed_data[1]
		#endregion
		
		# NOTE: This currently computes using just the created_date, as sum_ticket_count should total tickets regardless of if they were given a Completed time,
		# and sum_turnaround_times already checks for tickets that have a Completed time and only uses those.
		
		# filter by date if time_range is not set to default, which uses the whole dataset.
		if compute_range == true:
			var in_range: bool = false
			var created_date_array: Array = Array(created_date_data)
			
			# convert years to day values
			var created_year_days_conversion: int = (created_date_array[0] - 1) * 365
			var created_month_days_conversion: int = 0
			if created_date_array[1] > 1:
				for month: int in range(1, created_date_array[1] + 1):
					created_month_days_conversion += month_to_days(month)
			var created_sum_in_days: int = created_year_days_conversion + created_month_days_conversion + created_date_array[2]
			
			var start_year_days_conversion: int = (time_range["Start"][0] - 1) * 365
			var start_month_days_conversion: int = 0
			if time_range["Start"][1] > 1:
				for month: int in range(1, time_range["Start"][1] + 1):
					start_month_days_conversion += month_to_days(month)
			var start_sum_in_days: int = start_year_days_conversion + start_month_days_conversion + time_range["Start"][2]
			
			var end_year_days_conversion: int = (time_range["End"][0] - 1) * 365
			var end_month_days_conversion: int = 0
			if time_range["End"][1] > 1:
				for month: int in range(1, time_range["End"][1] + 1):
					end_month_days_conversion += month_to_days(month)
			var end_sum_in_days: int = end_year_days_conversion + end_month_days_conversion + time_range["End"][2]
			
			# if only the Start value is 0, only see if the data is before End.
			if time_range["Start"][0] == 0:
				if created_sum_in_days <= end_sum_in_days:
					in_range = true
			# if only the End value is 0, only see if the data is after Start.
			elif time_range["End"][0] == 0:
				if created_sum_in_days >= start_sum_in_days:
					in_range = true
			# if neither value is 0, use both ends of the range to search.
			else:
				if created_sum_in_days >= start_sum_in_days && created_sum_in_days <= end_sum_in_days:
					in_range = true
			
			# only process tickets in the date range.
			if in_range == true:
				sum_ticket_count(record, category)
				sum_turnaround_times(record, category)
		else:
			sum_ticket_count(record, category, technician)
			if technician == "Help Desk":
				sum_turnaround_times(record, category)
	
	# print data stored into dictionaries from sum_ticket_count.
	# NOTE: This function currently populates category_percentages, which is needed for graph visualization.
	print_data(category, technician)
	# get an average turnaround time using the above data.
	if technician == "Help Desk":
		avg_turnaround_times(category)
	
	print("\n")
	print("-------------------------")
	print("\n")

func sum_ticket_count(record: Dictionary, category: Array = [""], technician: String = "Help Desk") -> void:
	#print(record["Assigned To First Name"] + ": " + str(record["WorkOrderNo"]))

	# if a category was provided, determine if the given record (ticket) will be included in the dataset.
	if category[0] != "":
		var found_cat: bool = false
		for cat: String in category:
			# if the given category title (non case-sensitive) was not found in the ticket's title, return so the data is not included. 
			if record["Work Order Title"].findn(cat) != -1:
				found_cat = true
		if found_cat == false:
			return
	
	match record["WO Status"]:
		"Completed":
			closed_total = increment_dictionary_value_by_key(closed_total, record["Assigned To First Name"])
			closed_total[technician] += 1
		"In Progress":
			in_prog_total = increment_dictionary_value_by_key(in_prog_total, record["Assigned To First Name"])
			in_prog_total[technician] += 1
		"On Hold":
			on_hold_total = increment_dictionary_value_by_key(on_hold_total, record["Assigned To First Name"])
			on_hold_total[technician] += 1

func avg_turnaround_times(category: Array = [""]) -> void:
	if category[0] == "":
		for assignee: String in closed_total.keys():
			# TODO: Encapsulate these into functions.
			if closed_total[assignee] == 0: # skip people who didn't close any tickets
				continue
			#print("summed turnaround time: " + str(turnaround_time_sums[assignee]))
			print(assignee + "'s closed total: " + str(closed_total[assignee]))
			var avg: float = round_to_dec(turnaround_time_sums[assignee] / closed_total[assignee], ROUNDING_PLACE)
			print(assignee + "'s average turnaround time: " + str(avg) + " minutes." + "\n")
	else:
		for assignee: String in closed_total.keys():
			if closed_total[assignee] == 0: # skip people who didn't close any tickets
				continue
			#print("summed turnaround time in category " + category[0] + ": " + str(turnaround_time_sums[assignee]))
			print(assignee + "'s closed total in category " + category[0] + ": " + str(closed_total[assignee]))
			var avg: float = round_to_dec(turnaround_time_sums[assignee] / closed_total[assignee], ROUNDING_PLACE)
			print(assignee + "'s average turnaround time in category " + category[0] + ": " + str(avg) + " minutes." + "\n")

func sum_turnaround_times(record: Dictionary, category: Array = [""], include_multiple_days: bool = false) -> void:
	# if a category was provided, determine if the given record (ticket) will be included in the dataset.
	if category[0] != "":
		var found_cat: bool = false
		for cat: String in category:
		# if the given category title (non case-sensitive) was not found in the ticket's title, return so the data is not included. 
			if record["Work Order Title"].findn(cat) != -1:
				found_cat = true
		if found_cat == false:
			return
	
	var assignee: String = record["Assigned To First Name"]
	
	# obtain sub-strings from 'Originated Date' and 'Completed Date' fields that contain just what we need.
	var created_date: String = record["Originated Date"].left(10)
	var created_time: String = record["Originated Date"].right(9).substr(0, 5)
	var completed_date: String = record["Completed Date"].left(10)
	var completed_time: String = record["Completed Date"].right(9).substr(0, 5)
	
	# split the strings into arrays of floats, so that we can work with the numeric data.
	var created_date_data: PackedFloat64Array = created_date.split_floats("-")
	var completed_date_data: PackedFloat64Array = completed_date.split_floats("-")
	var created_time_data: PackedFloat64Array = created_time.split_floats(":")
	var completed_time_data: PackedFloat64Array = completed_time.split_floats(":")
	
	var turnaround_time_to_minutes: float
	
	# only parse data if all fields are filled out.
	if created_date_data.size() == 3 && completed_date_data.size() == 3:
		# offset times by seven hours as the data is misaligned.
		var offset_created_data: Array[PackedFloat64Array] = offset_date_and_time(created_date_data, created_time_data, HOUR_OFFSET)
		var offset_completed_data: Array[PackedFloat64Array] = offset_date_and_time(completed_date_data, completed_time_data, HOUR_OFFSET)
		
		# assign the adjusted values back to the existing variables.
		created_date_data = offset_created_data[0]
		created_time_data = offset_created_data[1]
		completed_date_data = offset_completed_data[0]
		completed_time_data = offset_completed_data[1]
		
		var turnaround_time_h: float
		var turnaround_time_m: float
		
		# only include tickets marked as 'Completed'.
		if record["WO Status"] == "Completed":
			# same-day logic
			if created_date_data == completed_date_data:
				turnaround_time_h = completed_time_data[0] - created_time_data[0]
				
				# if in the same hour, compute minutes normally.
				if turnaround_time_h == 0:
					turnaround_time_m = completed_time_data[1] - created_time_data[1]
				# otherwise, roll minutes over.
				else:
					if completed_time_data[1] < created_time_data[1]:
						turnaround_time_h -= 1
					
					turnaround_time_m = (60 - created_time_data[1]) + completed_time_data[1]
				
				# only include positive hour values - anything else suggests times were manually entered much later. this will skew the data significantly.
				if sign(turnaround_time_h) != -1:
					turnaround_time_to_minutes = (turnaround_time_h * 60) + turnaround_time_m
				
			# multi-day logic (this will skew the data quite a lot because these are outliers)
			else:
				if include_multiple_days:
					pass
	# if fields are missing, subtract one from the total ticket count for this person, or the average will get skewed.
	# this is necessary as sum_ticket_count does not filter in this way - it just gives a raw total.
	else:
		closed_total = decrement_dictionary_value_by_key(closed_total, assignee)
	
	# add turnaround_time_to_minutes to a dictionary for each person's total sum, for averaging later.
	if turnaround_time_sums.has(assignee):
		turnaround_time_sums[assignee] += turnaround_time_to_minutes
	else:
		turnaround_time_sums[assignee] = turnaround_time_to_minutes
	
	# add every ticket to the collective sum or the team.
	turnaround_time_sums["Help Desk"] += turnaround_time_to_minutes

func get_technician_percentages() -> void:
	for assignee: String in closed_total.keys():
		if assignee != "Help Desk" && assignee != "ITS":
			var technician_percentage: float = round_to_dec(float(closed_total[assignee] / float(closed_total["Help Desk"])) * 100.0, 2)
			technician_percentages[assignee] = technician_percentage

func print_data(category: Array = [""], technician: String = "Help Desk") -> void:
	# Only print data and populate category_percentages
	if closed_total.has(technician):
		if category[0] == "":
			print("Closed ticket total: " + str(closed_total))
			print("In Progress ticket total: " + str(in_prog_total) + "\n")
			#print("On hold ticket total: " + str(on_hold_total))
		else:
			print("Closed ticket total in category " + category[0] + ": " + str(closed_total))
			print("In Progress ticket total in category " + category[0] + ": " + str(in_prog_total) + "\n")
			# TODO: Update this function (and these lines) to decide who to print data for - see the spread of ticket types for just a specific technician, or the entire help desk?
			var category_percentage: float
			#if technician == "Help Desk":
			category_percentage = round_to_dec((float(closed_total[technician]) / float(closed_total_in_dataset)) * 100.0, 2)
			#else:
				#pass
			print(category[0] + " is " + str(category_percentage) + "% of the full dataset.")
			# FIXME: This needs to be done somewhere else, it's misleading to have it in here.
			category_percentages[category[0]] = category_percentage
			#print("On hold ticket total in category " + category[0] + ": " + str(on_hold_total))

func flush_dictionaries() -> void:
	turnaround_time_sums.clear()
	closed_total.clear()
	in_prog_total.clear()
	on_hold_total.clear()
	
	# just give help desk a default value in each dict to avoid checking if it exists already
	turnaround_time_sums["Help Desk"] = 0
	closed_total["Help Desk"] = 0
	in_prog_total["Help Desk"] = 0
	on_hold_total["Help Desk"] = 0
#endregion

#region Helper Functions
func increment_dictionary_value_by_key(dict: Dictionary, key: String) -> Dictionary:
	if dict.has(key):
		dict[key] += 1
	else:
		dict[key] = 1
	return dict

func decrement_dictionary_value_by_key(dict: Dictionary, key: String) -> Dictionary:
	if dict.has(key):
		dict[key] -= 1
	return dict

func offset_date_and_time(date_value: PackedFloat64Array, time_value: PackedFloat64Array, hr_offset: float) -> Array[PackedFloat64Array]:
	# if the hour value is less than the offset, the date is going to roll backwards.
	if time_value[0] < hr_offset:
		# update the hour value to roll back into the day before, regardless of that actual date.
		time_value[0] = FULL_DAY + (time_value[0] - hr_offset)
		# roll back the day
		date_value[2] -= 1
		# if rolling back the day leads it to equal 0, the month needs to be rolled back.
		if date_value[2] == 0:
			# roll back the month
			date_value[1] -= 1
			# if rolling back the month leads it to equal 0, the year needs to be rolled back.
			if date_value[1] == 0:
				# roll back the year
				date_value[0] -= 1
				
				# offset day to last day of december.
				date_value[1] = 12
				date_value[2] = 31
			# if the year does not roll back, calculate the day value using the new month.
			else:
				# TODO: Test out swapping this with month_to_days
				match date_value[1]:
					# 31-day months
					1, 3, 5, 7, 8, 10:
						date_value[2] = 31
					# 30-day months
					4, 6, 9, 11:
						date_value[2] = 30
					# february
					2:
						# leap-year feb.
						if (int(date_value[1]) % 4) == 0:
							date_value[2] = 29
						# non leap-year
						else:
							date_value[2] = 28
	# if the hour value is greater than the offset value, the date won't change, so just subtract.
	else:
		time_value[0] -= hr_offset
	
	var updated_date_and_time: Array[PackedFloat64Array] = [date_value, time_value]
	return updated_date_and_time

func round_to_dec(num: float, digit: int) -> float:
	return round(num * pow(10.0, digit)) / pow(10.0, digit)

func month_to_days(month: int) -> int:
	match month:
		# 31-day months
		1, 3, 5, 7, 8, 10:
			return 31
		# 30-day months
		4, 6, 9, 11:
			return 30
		# february
		2:
			# leap-year feb.
			if (month % 4) == 0:
				return 29
			# non leap-year
			else:
				return 28
		_:
			return 0

#endregion
