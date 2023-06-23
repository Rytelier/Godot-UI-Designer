@tool
extends EditorPlugin

var selection : EditorSelection
var undo : EditorUndoRedoManager
var designerMain : Control
var addContainer
var addContainerGroups = []
var canvasEditorControl
var initialized = false

var designerToggle : Button
var designerShow = true

var typesList
var typesListDefault = ['Control','Button','Panel']
var addItemButton : Button
var renameButton : Button

var controlParent : Control
var lastSelected : Node
var addToSelected = false
var toSelectedIcon = preload("res://Addons/UI Designer/Resources/To selected.svg")
var asNeighborIcon = preload("res://Addons/UI Designer/Resources/As neighbor.svg")
var parentCurrentLevel : Button

var renamePanel : PopupPanel
var renameTarget : Node

func _enter_tree():
	selection = get_editor_interface().get_selection()
	undo = get_undo_redo()
	designerMain = load("res://Addons/UI Designer/Resources/UI Designer.tscn").instantiate()
	
	designerToggle = Button.new()
	designerToggle.text = "UI Designer"
	designerToggle.toggle_mode = true
	designerToggle.button_pressed = true
	designerToggle.toggled.connect(ShowDesigner.bind())
	
	selection.selection_changed.connect(ShowDesignerButton.bind())
	selection.selection_changed.connect(UpdateSelected.bind()) #Set last selected control
	
	set_force_draw_over_forwarding_enabled()

func ShowDesignerButton():
	if selection.get_selected_nodes().size() != 0 and selection.get_selected_nodes()[0] is Control:
		if designerToggle.get_parent() == null: add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, designerToggle)
		if initialized: designerMain.visible = designerShow
	elif selection.get_selected_nodes().size() > 0 and not selection.get_selected_nodes()[0] is Control:
		if designerToggle.get_parent() != null: remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, designerToggle)
		if initialized: designerMain.visible = false

func ShowDesigner(b):
	if !initialized: return
	designerShow = b
	
	if designerShow:
		designerMain.visible = true
	else :
		designerMain.visible = false

func InitEditor():
	canvasEditorControl.add_child(designerMain)
	
	addContainer = designerMain.get_node("Add container")
	typesList = designerMain.get_node("Types")
	addItemButton = designerMain.get_node("Add item template")
	
	#Settings
	designerMain.get_node("Options").size.y = 0
	var toSelected = designerMain.get_node("Options/To selected")
	toSelected.toggled.connect(func(b): 
		addToSelected = b
		toSelected.icon = toSelectedIcon if b else asNeighborIcon
		)
	toSelected.size = Vector2.ZERO
	
	parentCurrentLevel = designerMain.get_node("Options/Parent level")
	
	#Quick actions
	var moveUp = designerMain.get_node("Move up")
	var moveDown = designerMain.get_node("Move down")
	moveUp.pressed.connect(MoveChild.bind(false))
	moveDown.pressed.connect(MoveChild.bind(true))
	
	#Add node container
	for child in addContainer.get_children(): child.queue_free()
	
	var idx = 0
	var list = typesList.get_children()
	list.reverse()
	for group in list:
		if addContainerGroups.size() <= idx:
			var box = BoxContainer.new()
			addContainer.add_child(box)
			addContainerGroups.append(box)
			idx += 1
		for type in group.get_children():
			var addButton : Button = addItemButton.duplicate()
			addContainerGroups[addContainerGroups.size()-1].add_child(addButton)
			addButton.visible = true
			if get_editor_interface().get_base_control().has_theme_icon(type.name, "EditorIcons"):
				addButton.icon = get_editor_interface().get_base_control().get_theme_icon(type.name, "EditorIcons")
			else:
				addButton.icon = load("res://Addons/UI Designer/Resources/Custom.svg")
			addButton.tooltip_text = type.name
			addButton.pressed.connect(AddItem.bind(type))
	
	#Rename
	renamePanel = designerMain.get_node("Rename panel")
	renamePanel.get_child(0).text_submitted.connect(RenameAndSetText.bind())
	renameButton = designerMain.get_node("Options/Rename")
	renameButton.pressed.connect(RenamePanelShow.bind())
	
	initialized = true
	
func _forward_canvas_force_draw_over_viewport(viewport_control):
	canvasEditorControl = viewport_control
	if !initialized: InitEditor()

func _exit_tree():
	designerMain.queue_free()
	designerToggle.queue_free()
	pass

func UpdateSelected():
	if selection.get_selected_nodes().size() > 0 and selection.get_selected_nodes()[0] is Control:
		lastSelected = selection.get_selected_nodes()[0]

func AddItem(item):
	if !is_instance_valid(lastSelected) or lastSelected.owner == null: return
	
	var newItem = item.duplicate()
	var parent
	var index = -1
	
	#Add to parent
	if not addToSelected:
		parent = lastSelected.get_parent()
		index = lastSelected.get_index() + 1
		if parent == null or not parent is Control:
			parent = lastSelected
			index = -1
	#Add to selected
	else:
		parent = lastSelected
		index = -1
	if not parent is Control: return
	
	var neighbors = parent.get_children()
	
	parent.add_child(newItem)
	
	undo.create_action("[UI Designer] Add node")
	
	newItem.owner = parent.get_tree().edited_scene_root
	if index != -1: parent.move_child(newItem, index)
	
	if parentCurrentLevel.button_pressed:
		for node in neighbors:
			node.reparent(newItem)
			node.owner = parent.get_tree().edited_scene_root
			#Owner is missing when node is reparented for some reason, so it needs to be reassigned again
			undo.add_undo_method(node, 'reparent', parent)
			var children = GetChilrenRecursive(node)
			undo.add_undo_property(node, 'owner', parent.get_tree().edited_scene_root)
			for c in children:
				c.owner = parent.get_tree().edited_scene_root
				undo.add_undo_property(c, 'owner', parent.get_tree().edited_scene_root)
		parentCurrentLevel.button_pressed = false
		
	undo.add_undo_method(newItem, 'queue_free')
	undo.add_undo_method(selection, 'add_node', lastSelected)
	
	selection.clear()
	selection.add_node(newItem)
	lastSelected = newItem
	get_editor_interface().edit_node(newItem)
	
	undo.commit_action()

func GetChilrenRecursive(node : Node) -> Array:
	var arr = []
	var children = node.get_children()
	for c in children:
		arr.append(c)
		arr.append_array(GetChilrenRecursive(c))
		
	return arr

func MoveChild(down):
	if !is_instance_valid(lastSelected) or lastSelected.owner == null: return
	
	undo.create_action("[UI Designer] Move child")
	
	var item = lastSelected
	if item == null: return
	var parent = item.get_parent()
	if parent == null: return
	
	undo.add_undo_method(parent, 'move_child', item, item.get_index())
	if down:
		undo.add_do_method(parent, 'move_child', item, item.get_index()+1)
		parent.move_child(item, item.get_index()+1)
	else:
		undo.add_do_method(parent, 'move_child', item.get_index()-1)
		parent.move_child(item, item.get_index()-1)
	
	undo.commit_action()

func RenamePanelShow():
	if !is_instance_valid(lastSelected) or lastSelected.owner == null: return
	
	renamePanel.position = Vector2i.ZERO
	renamePanel.popup()
	renamePanel.position += Vector2i(get_viewport().get_mouse_position())
	
	renameTarget = lastSelected
	renamePanel.get_child(0).text = ""
	renamePanel.get_child(0).grab_focus()

func RenameAndSetText(text):
	undo.create_action("[UI Designer] Rename and set text")
	
	if text != "": 
		undo.add_undo_property(renameTarget, 'name', renameTarget.name)
		undo.add_do_property(renameTarget, 'name', text)
		renameTarget.name = text
	if renameTarget.get("text") != null:
		undo.add_undo_property(renameTarget, 'text', renameTarget.text)
		undo.add_do_property(renameTarget, 'text', text)
		renameTarget.text = text
	undo.commit_action()
	
	renamePanel.hide()
