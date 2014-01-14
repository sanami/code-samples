# Whiteboard
class Whiteboard7.Models.Board extends Backbone.RelationalModel
  paramRoot: 'board'
  urlRoot: Routes.boards_path()

  accessible: ['board_name', 'board_access', 'board_lock_status', 'canvas_params']

  defaults: -> # don't share objects
    board_name: ''
    board_access: 'public_board'
    board_lock_status: 'unlock'
    board_members: [] # [ User, ... ]
    online_users: {}  # { connection_id => User, ... }

  # ...com/draw#adade4
  publicUrl: ->
    Routes.draw_url() + "\##{@get 'uid'}"

  # /draw#adade4
  publicPath: ->
    Routes.draw_path() + "\##{@get 'uid'}"

  boardTitle: (limit = 40) ->
    str = @get 'board_name'
    str = "Board ##{@get 'uid'}" if _.str.isBlank(str)
    str = _.str.strip(str)
    _.str.truncate(str, limit)

  boardUserLabel: (user = null, connection_id = null, limit = 100)->
    if user
      #str = "#{user.user_name || ''} <#{user.email}>"
      str = user.user_name || ''
    else
      str = "anon-#{connection_id}"

    str = _.str.strip(str)
    _.str.truncate(str, limit)

  boardCreationTime: ->
    moment(@get('created_at')).format('YYYY-MM-DD')

  addBoardMember: (user)->
    @get('board_members').push user
    @trigger 'change:board_members', this

  removeBoardMember: (user_id)->
    board_members = @get('board_members')
    for user, i in board_members
      if user.id == user_id
        board_members.splice(i, 1)
        @trigger 'change:board_members', this
        break

  isBoardMember: (user)->
    obj = _.find @get('board_members'), (it)->
      it.id == user.id
    !_.isUndefined obj

  addOnlineUser: (connection_id, user)->
    @get('online_users')[connection_id] = user
    @trigger 'change:online_users', this

  removeOnlineUser: (connection_id)->
    online_users = @get('online_users')
    if _.has(online_users, connection_id)
      delete @get('online_users')[connection_id]
      @trigger 'change:online_users', this

  onlineUser: (connection_id)->
    @get('online_users')[connection_id]

  # Download board objects
  fetchObjects: (params = {})->
    try
      settings =
        type: 'GET'
        url: Routes.file_board_path(@id)
        cache: false
        contents: { json: null } # disable JSON parsing
      _.extend settings, params

      settings.success = (data)->
        board_data = if _.str.isBlank(data)
          {}
        else
          $.parseJSON(data)
        params.success(board_data)

      $.ajax settings

    catch ex
      params.error(ex) if params.error

  # Reset connection info
  initConnection: (connection_id)->
    @connection_id = connection_id

  isOwnCommand: (cmd)->
    @connection_id == cmd.connection_id

  isOwnConnection: (connection_id)->
    @connection_id == connection_id

  toggleLockStatus: ->
    status = @get('board_lock_status')
    status = if status == 'lock' then 'unlock' else 'lock'

    @save board_lock_status: status, patch: true

  toggleBoardAccess: ->
    status = @get('board_access')
    status = if status == 'private_board' then 'public_board' else 'private_board'

    @save board_access: status, patch: true


class Whiteboard7.Collections.BoardsCollection extends Backbone.Collection
  model: Whiteboard7.Models.Board
  url: Routes.boards_path()

# Init
Whiteboard7.Models.Board.setup()
