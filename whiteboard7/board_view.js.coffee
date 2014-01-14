# Drawing board
class Whiteboard7.Views.BoardView extends Backbone.Marionette.ItemView
  template: JST['board']

  # Handlers for events from header/footer views
  footerEvents:
    'board:update_from_server': 'fetchObjects'
    'board:dump_objects': 'dump_objects'
    'board:loading_mode': 'setLoadingMode'
    'board:viewer_mode': (enable)-> @canvas.enableViewerMode(enable)
    'board:option:change': 'onBoardOptionChange'

  # Handlers for events from canvas view
  canvasEvents:
    'canvas:object:create': 'onCanvasObjectCreate'
    'canvas:object:modified': 'onCanvasObjectModified'
    'canvas:laser:move': (pt)->
      @sendCommand 'laser:move', point: pt
    'canvas:laser:flash': (pt)->
      @sendCommand 'laser:flash', point: pt

  # Events from connection
  channelEvents:
    'channel:joined': 'onChannelJoined'
    'channel:failed': 'onChannelFailed'
    'channel:object:create': 'onChannelObjectCreate'
    'channel:object:modified': 'onChannelObjectModified'
    'channel:laser:move': 'onChannelLaserMove'
    'channel:laser:flash': 'onChannelLaserFlash'
    'channel:board:clear': 'onChannelBoardClear'
    'channel:option:change': 'onChannelOptionChange'

  # Events from board model
  modelEvents:
    'change': 'onBoardUpdate'

  initialize: (options)->
    @options = options
    @laser_pointers = {}

    # Bind events from views
    Marionette.bindEntityEvents(this, options.footer, @footerEvents)

    @channel = new Whiteboard7.Models.BoardChannel()
    Marionette.bindEntityEvents(this, @channel, @channelEvents)

    if options.board_uid
      # Join existing board
      @model = WhiteboardApp.current_user.findBoardByUid(options.board_uid)
      if @model
        @model.set canvas_el: "canvas_#{@cid}"
      else
        @model = new Whiteboard7.Models.Board(canvas_el: "canvas_#{@cid}", uid: options.board_uid)

    else
      # New board
      @model = new Whiteboard7.Models.Board(canvas_el: "canvas_#{@cid}")
      @addMessage('New board started')

    @setBoardModel(@model)

    if @model.get('uid')
      @openChannel()

  # View is on page
  onDomRefresh: ->
    @canvas = new Whiteboard7.Views.CanvasView(el: @$('.canvas_wrapper'), canvas_el: @model.get('canvas_el'), model: @options.state)
    Marionette.bindEntityEvents(this, @canvas, @canvasEvents)

    # Connecting to channel
    if @channel.isConnected()
      @setLoadingMode(true)

    window.c = @canvas.canvas
    window.s = @options.state
    window.v = @canvas
    window.b = this
    pp c, s, v, b

    @clearCanvasObjects()

  # Clear resources
  onClose: ->
    if @canvas
      @canvas.close()
      Marionette.unbindEntityEvents(this, @canvas, @canvasEvents)

    Marionette.unbindEntityEvents(this, @options.footer, @footerEvents)

    Marionette.unbindEntityEvents(this, @channel, @channelEvents)

    @closeChannel()

  # Private channel for this board
  openChannel: ->
    @channel.openChannel() if WhiteboardApp.dispatcher

  # Close existing channel
  closeChannel: ->
    @channel.closeChannel() if WhiteboardApp.dispatcher

  # Send command into channel
  sendCommand: (command, params)->
    return unless WhiteboardApp.dispatcher

    if WhiteboardApp.current_user.canPostBoard(@model)
      @postToServer()
    else
      @channel.sendCommand(command, params)

  # Private channel joined
  onChannelJoined: (params)=>
    pp 'onChannelJoined', params
    existing_model = Whiteboard7.Models.Board.find(params.board.id)

    if existing_model
      existing_model.set params.board
      @setBoardModel(existing_model)
    else
      @model.set params.board
      @setBoardModel(@model)

    @model.initConnection params.connection_id

    board_uid = @model.get('uid')
    @addMessage "Board #{board_uid} opened"

    @fetchObjects()

    Backbone.history.navigate(board_uid, trigger: false)

  # Private channel join failed
  onChannelFailed: (reason)=>
    @addMessage "Board #{@model.get('uid')} open failed:", reason.message
    @closeChannel()
    @model.unset('uid')

    WhiteboardApp.current_user.removeBoard(@model)
    Backbone.history.navigate('', trigger: false)

    @setLoadingMode(false)

  clearCanvasObjects: ->
    @canvas.removeAllObjects()
    @owner_object_id = 0
    @own_objects = {}
    @all_objects = {}

  # Set canvas objects
  resetCanvasObjects: (board_data)->
    @clearCanvasObjects()

    @options.state.set board_data.options

    json_objects = board_data.objects
    if _.isEmpty(json_objects)
      # Just clear
      @canvas.renderAllObjects()
    else
      # Render after all objects added
      render_fn = _.after json_objects.length, =>
        @canvas.renderAllObjects()

      for data in json_objects
        @canvas.addObject data.object, (canvas_obj)=>
          @all_objects[data.object_id] = canvas_obj if canvas_obj
          render_fn()

  # New object created
  onCanvasObjectCreate: (canvas_obj)->
    owner_object_id = ++@owner_object_id
    @own_objects[owner_object_id] = canvas_obj

    data = @canvas.serializeObject(canvas_obj)
    @sendCommand 'object:create', object: data, owner_object_id: owner_object_id

  # New object received
  onChannelObjectCreate: (params)=>
    #pp 'onChannelObjectCreate', params
    own_object = @model.isOwnCommand(params)

    # Async handler
    object_add_fn = (canvas_obj)=>
      @all_objects[params.object_id] = canvas_obj if canvas_obj

      # Move lasers to front
      @canvas.updateLaserPointers(@laser_pointers)

      # Render scene
      @canvas.renderAllObjects()

    if own_object
      canvas_obj = @own_objects[params.owner_object_id]
      delete @own_objects[params.owner_object_id]

      object_add_fn(canvas_obj)
    else
      json_obj = @canvas.deserializeObject(params.object)
      @canvas.addObject(json_obj, object_add_fn)

  # Canvas object modified
  onCanvasObjectModified: (canvas_obj)->
    canvas_obj_id = null
    for obj_id, obj of @all_objects
      if obj == canvas_obj
        canvas_obj_id = obj_id
        break

    if canvas_obj_id
      data = @canvas.serializeObject(canvas_obj)
      @sendCommand 'object:modified', object: data, object_id: canvas_obj_id

  # Update existing modified
  onChannelObjectModified: (params)->
    own_object = @model.isOwnCommand(params)
    unless own_object
      canvas_obj = @all_objects[params.object_id]
      json_obj = @canvas.deserializeObject(params.object)

      @canvas.updateObject canvas_obj, json_obj, (new_canvas_obj)=>
        @all_objects[params.object_id] = new_canvas_obj


  # Presentation mode update
  onChannelLaserMove: (params)=>
    own_pointer = @model.isOwnCommand(params)
    laser_pointer = @laser_pointers[params.connection_id]

    if laser_pointer
      if params.point
        # Move
        @canvas.moveLaserPointer(laser_pointer, params.point) unless own_pointer
      else
        # Remove
        @canvas.removeLaserPointer(laser_pointer) unless own_pointer
        delete @laser_pointers[params.connection_id]

    else if params.point
      # Create
      laser_pointer = @canvas.createLaserPointer(params.point, own_pointer)
      if laser_pointer
        @laser_pointers[params.connection_id] = laser_pointer

  # Presentation mode flash
  onChannelLaserFlash: (params)=>
    @onChannelLaserMove(params) # create

    own_pointer = @model.isOwnCommand(params)
    laser_pointer = @laser_pointers[params.connection_id]
    if laser_pointer && !own_pointer
      @canvas.flashLaserPointer(laser_pointer)

  # Remove board objects
  onChannelBoardClear: (params)->
    unless @model.isOwnCommand(params)
      @clearCanvasObjects()

      # Render scene
      @canvas.renderAllObjects()

  # Update canvas options
  onChannelOptionChange: (params)->
    unless @model.isOwnCommand(params)
      @options.state.set params.options

  # Post board to server
  postToServer: ->
    pp 'postToServer'
    return if @model.get('uid') || @model.get('canvas_params') # already posted

    @setLoadingMode(true)

    @model.save { canvas_params: { canvas_objects: @canvas.serializeAllObjects(), canvas_options: @canvas.getCanvasOptions() } },
      success: (model, response, options)=>
        pp 'success', model
        @addMessage "New board posted: #{model.get('uid')}"
        model.unset 'canvas_params'

        # Connect to channel, fetch objects back with assigned 'id'
        @openChannel()

        # List
        WhiteboardApp.current_user.addOwnBoard(model)
        WhiteboardApp.current_user.trigger('board:post')

      error: (model, xhr, options)=>
        pp 'error', arguments
        @addMessage "Board post failed"
        @setLoadingMode(false)
        model.unset 'canvas_params'

  # Get board objects from server
  fetchObjects: ->
    pp 'fetchObjects'
    return unless @model.get('uid')

    @setLoadingMode(true)

    @model.fetchObjects
      error: =>
        pp 'error', arguments
        @setLoadingMode(false)
      success: (board_data)=>
        pp 'success'#, board_data
        @canvas.showLoader(false) # hide loader freeze
        _.defer =>
          @resetCanvasObjects(board_data)
          @setLoadingMode(false)

  # Clear immediately
  clearCanvas: ->
    @clearCanvasObjects()
    @canvas.renderAllObjects()

  # Commands
  clearBoard: ->
    @sendCommand 'board:clear'
    @clearCanvas()

  setLoadingMode: (enable)->
    if enable
      @canvas.enableLoadingMode(true)
    else if WhiteboardApp.current_user.canModifyBoard(@model)
      @canvas.enableLoadingMode(false)
    else
      @canvas.enableViewerMode(true)

  onBoardOptionChange: (options)->
    @sendCommand 'option:change', options: options

  onBoardUpdate: ->
    if @model.hasChanged('board_lock_status')
      can_modify = WhiteboardApp.current_user.canModifyBoard(@model)
      @canvas.enableViewerMode(!can_modify)

  addMessage: ->
    WhiteboardApp.vent.trigger 'message', arguments

  hasNotSavedChanges: ->
    @model.isNew() && !@canvas.isEmpty()

  setBoardModel: (existing_model)->
    if @model
      Marionette.unbindEntityEvents(this, @model, @modelEvents)

    @model = existing_model
    @channel.board_model = @model

    Marionette.bindEntityEvents(this, @model, @modelEvents)

    if WhiteboardApp.current_user.get('current_board') == @model
      WhiteboardApp.current_user.trigger('change:current_board')
    else
      WhiteboardApp.current_user.set(current_board: @model)

  # Test
  dump_objects: ->
    pp 'dump_objects', @canvas.canvas.toObject()
