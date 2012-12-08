debug = true
log = () ->
  return if not debug
  console.log.apply console, arguments

class Comment extends Backbone.Model
  defaults: () ->
    parent: null
    children: new CommentCollection()
    user: null
    content: null
    # HNES display-state variables
    collapsed: false
    hidden: false
    selected: false
  initialize: () ->
    @on 'change:collapsed', (model, collapsed) =>
      if collapsed
        # collapsing a comment hides all its children
        @get('children').each (child) -> child.set { hidden: true }
      else
        # expanding a comment shows all the children and expands them
        @get('children').each (child) ->
          child.set { hidden: false, collapsed: false }
    @on 'change:hidden', (model, hidden) =>
      @get('children').each (child) -> child.set { hidden: hidden }
  tree_size: () =>
    1 + @get('children').chain().invoke('tree_size').reduce(((a, b) -> a + b), 0).value()

class CommentCollection extends Backbone.Collection
  model: Comment
  move_selection: (direction) =>
    # select the next non-hidden comment
    current_selection = @where({ selected: true })[0]
    current_selection_i = @indexOf(current_selection)
    new_selection_i = current_selection_i
    while true
      new_selection_i += direction
      return current_selection if not (0 <= new_selection_i < @length)
      new_selection = @at new_selection_i
      break if not new_selection.get('hidden')
    current_selection.set 'selected', false
    new_selection.set 'selected', true
    new_selection

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
    console.log 'render!'
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

class CommentView extends Backbone.View
  initialize: (options) ->
    @model.on 'change:selected', (model, selected) =>
      @$el.toggleClass 'selected', selected
      ensure_in_viewport @el if selected
    @model.on 'change:collapsed', (model, collapsed) =>
      log 'change:collapsed', collapsed, @model.get('user')
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
  comments = new CommentCollection()
  comment_views = []
  last_comment_at_depth = {} # map from depth to last comment seen at that depth. used to fill
  $('table:first > tbody > tr:nth-child(3):first > td:first > table:eq(1) > tbody > tr').each () ->
    $row = $(this)
    depth  = parseInt($row.find('img:first').attr('width')) / 40
    parent = last_comment_at_depth["#{depth-1}"]
    comment = new Comment
      user     : $row.find('table > tbody > tr:first > td:last > :first .comhead a:first').text()
      content  : $row.find('table > tbody > tr:first > td:last .comment').text()
      depth    : depth
      parent   : parent
    last_comment_at_depth["#{depth}"] = comment # next we see at depth+1 will have this asa parent
    parent.get('children').add comment if parent?
    comments.add comment
    comment_views.push new CommentView el: $(this), model: comment
  log 'COMMENTS', comments.models

  # TODO: track this state more formally
  comments.at(0).set 'selected', true
  selected_comment = comments.at 0

  $('body').on 'keypress', (e) ->
    log e.keyCode
    switch e.keyCode
      when 74, 106 # j
        selected_comment = comments.move_selection 1
      when 75, 107 # k
        selected_comment = comments.move_selection -1
      when 13 # Enter
        selected_comment.set 'collapsed', (not selected_comment.get('collapsed'))
      when 82, 114  # r
        comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
        comment_view.reply()
      when 65, 97 # a
        comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
        comment_view.vote 'up'
      when 90, 122 # z
        comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
        comment_view.vote 'down'
      when 85, 117 # u
        comment_view = _(comment_views).find (view) -> view.model.cid is selected_comment.cid
        comment_view.open_user()
