tool
extends MMGenBase
class_name MMGenRemote

"""
Remote can be used to control parameters from several generators in the same graph
"""

var widgets = []

func can_be_deleted() -> bool:
	return name != "gen_parameters"

func set_widgets(w : Array) -> void:
	widgets = w
	fix()

func get_widget(n : String) -> Dictionary:
	for w in widgets:
		if w.name == n:
			return w
	return {}

func get_next_widget_name():
	var i = 0
	while true:
		var param_name = "param"+str(i)
		var used = false
		for w in widgets:
			if w.has("name") and w.name == param_name:
				used = true
				break
		if !used:
			return param_name
		i += 1

func fix() -> void:
	# Make sure all widgets have a name
	var i = 0
	for w in widgets:
		if !w.has("name"):
			w.name = get_next_widget_name()
			print("Named "+w.name)
	var parent = get_parent()
	if parent == null:
		return
	var updated_widgets : Array = []
	var removed_widgets = false
	for w in widgets:
		var updated_linked_widgets : Array = []
		for l in w.linked_widgets:
			var linked_widget : MMGenBase = parent.get_node(l.node)
			if linked_widget != null and linked_widget.get_parameter_def(l.widget).size() > 0:
				updated_linked_widgets.push_back(l)
		if updated_linked_widgets.size() == 0:
			removed_widgets = true
			continue
		w.linked_widgets = updated_linked_widgets
		updated_widgets.push_back(w)
		if !parameters.has(w.name):
			match w.type:
				"config_control":
					parameters[w.name] = 0
				"linked_control":
					# Should get current value of a linked widget
					parameters[w.name] = 0
	if removed_widgets:
		widgets = updated_widgets
		emit_signal("parameter_changed", "__update_all__", null)

func get_type() -> String:
	return "remote"

func get_type_name() -> String:
	return "Parameters" if name == "gen_parameters" else "Remote"

func get_parameter_defs() -> Array:
	var rv = []
	var i = 0
	for w in widgets:
		match w.type:
			"config_control":
				var p : Dictionary = { name=w.name, label=w.label, type="enum", values=[] }
				var configurations = w.configurations.keys()
				configurations.sort()
				for c in configurations:
					p.values.push_back({ name=c, value=c })
				rv.append(p)
				i += 1
			"linked_control":
				var linked = w.linked_widgets[0]
				var p : Dictionary
				if linked != null && is_inside_tree():
					var gen = get_parent().get_node(linked.node)
					if gen != null:
						var gen_params = gen.get_parameter_defs()
						for pd in gen_params:
							if pd.name == linked.widget:
								p = pd.duplicate(true)
								break
				p.name = w.name
				p.label = w.label
				rv.append(p)
				i += 1
			_:
				print("Unsupported widget of type "+str(w.type))
	return rv

func set_parameter(p : String, v) -> void:
	var parent = get_parent()
	if parent == null:
		return
	var widget = get_widget(p)
	match widget.type:
		"linked_control":
			for w in widget.linked_widgets:
				parent.get_node(w.node).set_parameter(w.widget, v)
		"config_control":
			if v < widget.configurations.size():
				var configurations = widget.configurations.keys()
				configurations.sort()
				for w in widget.configurations[configurations[v]]:
					var node = parent.get_node(w.node)
					if node != null:
						node.set_parameter(w.widget, MMType.deserialize_value(w.value))
			else:
				# incorrect configuration index
				print("error: incorrect config control parameter value")
				return
	.set_parameter(p, v)
	if name == "gen_parameters":
		get_parent().parameters[p] = v

func _serialize(data: Dictionary) -> Dictionary:
	data.type = "remote"
	data.widgets = widgets
	return data

func create_linked_control(label : String) -> String:
	var n = get_next_widget_name()
	widgets.push_back({ name=n, label=label, type="linked_control", linked_widgets=[] })
	return n

func create_config_control(label : String) -> String:
	var n = get_next_widget_name()
	widgets.push_back({ name=n, label=label, type="config_control", linked_widgets=[], configurations={} })
	return n

func set_label(widget_name : String, new_label : String) -> void:
	get_widget(widget_name).label = new_label

func can_link_parameter(widget_name : String, generator : MMGenBase, param : String) -> bool:
	var widget : Dictionary = get_widget(widget_name)
	if !widget.linked_widgets.empty():
		# Check if the param is already linked
		for lw in widget.linked_widgets:
			if lw.node == generator.name and lw.widget == param:
				return false
		# Check the parameter type
		var linked : Dictionary = widget.linked_widgets[0]
		var linked_generator : MMGenBase = get_parent().get_node(linked.node)
		var linked_parameter : Dictionary = linked_generator.get_parameter_def(linked.widget)
		var parameter : Dictionary = generator.get_parameter_def(param)
		if parameter.type != linked_parameter.type:
			return false
		match parameter.type:
			"enum":
				if to_json(linked_parameter.values) != to_json(parameter.values):
					return false
	return true

func link_parameter(widget_name : String, generator : MMGenBase, param : String) -> void:
	if !can_link_parameter(widget_name, generator, param):
		return
	var widget : Dictionary = get_widget(widget_name)
	widget.linked_widgets.push_back({ node=generator.name, widget=param })
	if widget.linked_widgets.size() == 1:
		match widget.type:
			"linked_control":
				parameters[widget_name] = generator.parameters[param]
			"config_control":
				parameters[widget_name] = 0
	emit_signal("parameter_changed", "__update_all__", null)

func remove_parameter(widget_name : String) -> void:
	for i in range(widgets.size()):
		if widgets[i].name == widget_name:
			widgets.remove(i)
			break
	emit_signal("parameter_changed", "__update_all__", null)

func add_configuration(widget_name : String, config_name : String) -> void:
	var widget = get_widget(widget_name)
	if widget.type == "config_control":
		widget.configurations[config_name] = []
		var configurations = widget.configurations.keys()
		configurations.sort()
		parameters[widget.name] = configurations.find(config_name)
		update_configuration(widget_name, config_name)

func update_configuration(widget_name : String, config_name : String) -> void:
	var widget = get_widget(widget_name)
	if widget.type == "config_control":
		var c = []
		var parent = get_parent()
		for w in widget.linked_widgets:
			var g = parent.get_node(w.node)
			if g != null:
				var value = MMType.serialize_value(g.parameters[w.widget])
				c.push_back({ node=w.node, widget=w.widget, value=value })
		widget.configurations[config_name] = c
		emit_signal("parameter_changed", "__update_all__", null)

func remove_configuration(widget_name : String, config_name : String) -> void:
	var widget = get_widget(widget_name)
	if widget.type == "config_control":
		widget.configurations.erase(config_name)
		emit_signal("parameter_changed", "__update_all__", null)
