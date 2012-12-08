debug = true
log = () ->
  return if not debug
  console.log.apply console, arguments

# doubly-linked list of selectable things
class SelectableModel extends Backbone.Model
  defaults:
    selected: false
    next: null
    prev: null
  next: () =>
    if @get('next')
      @set { selected: false }
      @get('next').set { selected: true }
      return @get('next')
    @
  prev: () =>
    if @get('prev')
      @set { selected: false }
      @get('prev').set { selected: true }
      return @get('prev')
    @

class Reply extends SelectableModel

class Comment extends SelectableModel
  defaults: () ->
    parent: null
    children: []
    user: null
    content: null
    # HNES display-state variables
    collapsed: false
    hidden: false
  initialize: () ->
    @on 'change:collapsed', (model, collapsed) =>
      if collapsed
        # collapsing a comment hides all its children
        _(@get('children')).each (child) -> child.set { hidden: true }
      else
        # expanding a comment shows all the children and expands them
        _(@get('children')).each (child) ->
          child.set { hidden: false, collapsed: false }
    @on 'change:hidden', (model, hidden) =>
      _(@get('children')).each (child) -> child.set { hidden: hidden }
  tree_size: () =>
    1 + _(@get('children')).chain().invoke('tree_size').reduce(((a, b) -> a + b), 0).value()
  # override next/prev to skip hidden comments
  next: () => @move 1
  prev: () => @move -1
  move: (direction) =>
    # select the next non-hidden comment
    current_selection = @
    current_selection_i = @collection.indexOf current_selection
    new_selection_i = current_selection_i
    while true
      new_selection_i += direction
      return current_selection if not (0 <= new_selection_i < @collection.length)
      new_selection = @collection.at new_selection_i
      break if not new_selection.get('hidden')
    current_selection.set { selected: false }
    new_selection.set { selected: true }
    new_selection

class SelectableCollection extends Backbone.Collection
  model: SelectableModel

# TODO
#  - expand browsing to elements above the fold:
#    - factor out a SelectableView that does outlining and binds/unbinds keyhandler on
#      select/deselect
#    - make a linkedlist of selectable views?
#    - select comment box (tab to enter)
#    - select article (upvote, enter to follow link, u to follow user)
#    - top nav
#      - a/d to move left/right (with wrap around behavior)
#  - browsable bottom nav
#    - todo v2
#  - convert all window.opens to use chrome.tabs
#  - help modal when you press 'h'

ensure_in_viewport = (div) ->
  scroll_pos = $(document).scrollTop()
  rect = div.getBoundingClientRect()
  hidden_lower_pixels = rect.bottom - window.innerHeight
  $(document).scrollTop(scroll_pos + hidden_lower_pixels + 5) if hidden_lower_pixels > 0
  $(document).scrollTop(scroll_pos + rect.top - 5) if rect.top < 0

class CollapseToggle extends Backbone.View
  events: { click: 'click' }
  initialize: (options) ->
    @model.on 'change:collapsed', @render
    @render()
  click: =>
    @model.set 'collapsed', (not @model.get('collapsed'))
  render: =>
    @$el.html(if @model.get('collapsed') then "[+] (#{@model.tree_size()-1} children)" else '[-]')

class KeyNavAnnotation extends Backbone.View
  initialize: (options) ->
    @key = options.key
    @href = options.href
    @model.on 'change:selected', @render
    @model.on 'change:selected', (model, selected) =>
      if selected
        $('body').on 'keypress', @key_listener
      else
        $('body').off 'keypress', @key_listener
    @render()
  key_listener: (e) =>
    if e.keyCode is (48 + @key)
      window.open @href
  render: =>
    @$el.html(if @model.get('selected') then "[#{@key}]" else "")

class SelectableView extends Backbone.View
  initialize: (options) ->
    @model.on 'change:selected', (model, selected) =>
      @$el.toggleClass 'selected', selected
      ensure_in_viewport @el if selected

class CommentView extends SelectableView
  initialize: (options) ->
    super options
    @model.on 'change:collapsed', (model, collapsed) =>
      if collapsed then @collapse() else @show()
    @model.on 'change:hidden', (model, hidden) =>
      if hidden then @hide() else @show()

    # subview: [+/-] collapse toggle
    @$el.find('span.comhead').append(toggle_el = @make 'span', { class: 'collapse' })
    @collapse_toggle = new CollapseToggle { el: toggle_el, model: @model }

    # subview: link hotkeys
    @annotations = []
    _(@$el.find('td:eq(3) .comment a')).each (link) =>
      $link = $(link)
      return if $link.text() is 'reply'
      return if @annotations.length is 9 # no more single digit numbers
      key = @annotations.length + 1
      href = $link.attr('href')
      annotation_el = @make 'span',
        title: "press #{key} to open link"
        class: 'keyNavAnnotation'
      $link.after annotation_el
      @annotations.push new KeyNavAnnotation
        el: annotation_el
        model: @model
        key: key
        href: href

  original_styles: () =>
    # if altering any styles in hide/collapse, store the original here
    @$el.find('td:eq(2) > center').removeAttr 'style' # comment depth spacer is unstyled
    @$el.find('td:eq(3) div').attr 'style', 'margin-top:2px; margin-bottom:-10px;'
  show: () =>
    log "showing comment by '#{@model.get 'user'}'"
    @$el.show()
    @original_styles()
    @$el.find('td:eq(2) > center').children().show() # voting arrows
    @$el.find('td:eq(3)').children().show() # comment body
  hide: () =>
    log "hiding comment by '#{@model.get 'user'}'"
    @$el.hide()
  collapse: () =>
    log "collapsing comment by '#{@model.get 'user'}'"
    # the height of the voting area controls is one way to ctrl the height of the username area
    @$el.find('td:eq(2) > center').attr 'style', 'width:14px; height:18px;'
    @$el.find('td:eq(2) > center').children().hide() # voting arrows
    @$el.find('td:eq(3) > :not(:first-child)').hide() # hide all but the username <td></td>
    # get rid of inline style, it messes up alignment of username in selection box
    @$el.find('td:eq(3) div').attr 'style', 'margin-top:0px'
  vote: (dir) =>
    return if not (vote_link = @$el.find("td:eq(2) center a[id^=#{dir}_]"))
    for d in ['up', 'down']
      @$el.find("td:eq(2) center a[id^=#{d}_]")?[0].style.visibility = 'hidden'
    (new Image()).src = vote_link.attr 'href'
  reply: (new_window=false) =>
    return if not (link = @$el.find('p:last a')?.attr('href'))
    if new_window then window.open(link) else window.location = link
  open_user: (new_window=false) =>
    return if not (link = @$el.find('td:eq(3) a:eq(0)')?.attr('href'))
    if new_window then window.open(link) else window.location = link

# traverse the page for comments
$(document).ready () ->
  selectable_things = new SelectableCollection()
  comment_views = []
  last_comment_at_depth = {} # map from depth to last comment seen at that depth. used to fill
  last_comment = null
  $('table:first > tbody > tr:nth-child(3):first > td:first > table:eq(1) > tbody > tr').each () ->
    $row = $(this)
    depth  = parseInt($row.find('img:first').attr('width')) / 40
    parent = last_comment_at_depth["#{depth-1}"]
    comment = new Comment
      user     : $row.find('table > tbody > tr:first > td:last > :first .comhead a:first').text()
      content  : $row.find('table > tbody > tr:first > td:last .comment').text()
      depth    : depth
      parent   : parent
      prev     : last_comment
    last_comment?.set { next: comment }
    parent.get('children').push comment if parent?
    selectable_things.add comment
    comment_views.push new CommentView el: $(this), model: comment
    last_comment = comment
    last_comment_at_depth["#{depth}"] = comment # next we see at depth+1 will have this asa parent
  log 'COMMENTS', selectable_things.models, selectable_things.at(0).collection

  # TODO: track this state more formally
  selectable_things.at(0).set 'selected', true
  selected_thing = selectable_things.at 0

  $('body').on 'keypress', (e) ->
    #log e.keyCode
    switch e.keyCode
      when 74, 106 # j
        selected_thing = selected_thing.next()
        log 'selected', selected_thing.toJSON()
      when 75, 107 # k
        selected_thing = selected_thing.prev()
        log 'selected', selected_thing.toJSON()
      when 13 # Enter
        if selected_thing instanceof Comment
          selected_thing.set 'collapsed', (not selected_thing.get('collapsed'))
      when 82, 114  # r
        if selected_thing instanceof Comment
          log 'model.view', selected_thing.view
          comment_view = _(comment_views).find (view) -> view.model.cid is selected_thing.cid
          comment_view.reply()
      when 65, 97 # a
        if selected_thing instanceof Comment
          comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
          comment_view.vote 'up'
      when 90, 122 # z
        if selected_thing instanceof Comment
          comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
          comment_view.vote 'down'
      when 85, 117 # u
        if selected_thing instanceof Comment
          comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
          comment_view.open_user()
