debug = true
log = () ->
  return if not debug
  console.log.apply console, arguments

# doubly-linked list of selectable things that can respond to keypresses when in selected state
class SelectableModel extends Backbone.Model
  defaults:
    selected: false
    next: null
    prev: null
  initialize: =>
    @on 'change:selected', (model, selected) =>
      if not selected
        key.deleteScope 'all' # clears out keybindings of previous selection
      else
        key.setScope 'all'
        @keybindings()
  move_to: (attr) =>
    return @set({ selected: false }).get(attr).set({ selected: true }) if @get(attr)
    @
  next: => @move_to 'next'
  prev: => @move_to 'prev'
  keybindings: () =>
    key 'j', @next
    key 'k', @prev

# adapted from window.vote in the HN source. used for voting on comments and submissions
vote = (id) ->
  item = _(id.split(/_/)).last()
  $("##{dir}_#{item}")?[0].style.visibility = 'hidden' for dir in ['up', 'down']
  (new Image()).src = $("##{id}").attr 'href'

class Submission extends SelectableModel
  @create: (submission_el) ->
    new Submission
      title: submission_el.find('.title a').text()
      href: submission_el.find('.title a')?.attr('href')
      user: submission_el.next().find('a[href^="user"]')?.text()
      upvote_link_id: submission_el.find('a[href^="vote"]')?.attr('id')
      flag_href: submission_el.next().find('a[href^="/r?fnid"]')?.attr('href')
      comments_href: submission_el.next().find('a[href^="item"]')?.attr('href')

  keybindings: () =>
    # enter: follow submission link
    # u: follow user link in comment or submission
    # a: upvote
    # c: see comments
    # f: flag/unflag
    key 'enter', () =>
      window.open(@get('href')) if @get('href') # Show HN => no link
    key 'u', () => window.open "/user?id=#{@get('user')}"
    key 'a', () => vote @get('upvote_link_id')
    key 'c', () => window.open @get('comments_href')
    key 'f', () =>
      window.open(@get('flag_href')) if @get('flag_href')
    super

class AddComment extends SelectableModel
  keybindings: () =>
    key 'tab', () =>
      @trigger 'focus', 'textarea'
      false # don't double-tab
    super

class Comment extends SelectableModel
  defaults: () ->
    parent: null
    children: []
    user: null
    content: null
    links: []
    # HNES display-state variables
    collapsed: false
    hidden: false
  initialize: =>
    super
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
    attr = if direction > 0 then 'next' else 'prev'
    while new_selection = (new_selection or @).get(attr)
      break if not new_selection.get('hidden')
    @set { selected: false } if new_selection?
    new_selection?.set { selected: true }
    new_selection or @
  keybindings: () =>
    # 1-9: link annotation hotkeys
    # a,z: {up,down}vote
    # r: reply
    # u: user's profile
    # enter: collapse
    _([1..9]).each (index) =>
      key "#{index}", () =>
        window.open(@get('links')[index]) if @get('links')[index]
    key 'a', () => vote @get('upvote_link_id')
    key 'z', () => vote @get('downvote_link_id')
    key 'r', () =>
      window.open(@get('reply_href')) if @get('reply_href')
    key 'u', () => window.open "/user?id=#{@get('user')}"
    key 'enter', () => @set 'collapsed', !@get('collapsed')
    super

class SelectableCollection extends Backbone.Collection
  model: SelectableModel

# TODO
#  - make top nav items selectable
#  - bottom nav or "more comments" selectable
#  - convert all window.opens to use chrome.tabs
#  - help modal when you press '?'

ensure_in_viewport = (div) ->
  scroll_pos = $(document).scrollTop()
  rect = div.getBoundingClientRect()
  hidden_lower_pixels = rect.bottom - window.innerHeight
  $(document).scrollTop(scroll_pos + hidden_lower_pixels + 5) if hidden_lower_pixels > 0
  $(document).scrollTop(scroll_pos + rect.top - 5) if rect.top < 0

# base view for all components:
#  - toggles a 'selected' class when selected (potentially on sister elements as well)
#  - ensures the selected div is viewable in the viewport
class SelectableView extends Backbone.View
  initialize: (options) =>
    @model.on 'change:selected', (model, selected) =>
      @$el.toggleClass 'selected', selected
      ensure_in_viewport @el if selected
    @sister_views = []
    _(options.sister_els or []).each (sister_el) =>
      @sister_views.push = new SelectableView({el: sister_el, model: @model})

class SubmissionView extends SelectableView

class AddCommentView extends SelectableView
  initialize: (options) =>
    super
    @model.on 'focus', (tag) => @$el.find(tag)?.focus()

snark = _.once () -> alert 'WHY ARE YOU USING THE MOUSE???'
class CollapseToggle extends Backbone.View
  events: { click: 'click' }
  initialize: (options) =>
    @model.on 'change:collapsed', @render
    @render()
  render: =>
    @$el.html(if @model.get('collapsed') then "[+] (#{@model.tree_size()-1} children)" else '[-]')
  click: =>
    snark()
    @model.set 'collapsed', (not @model.get('collapsed'))

class KeyNavAnnotation extends Backbone.View
  initialize: (options) =>
    @hotkey = options.hotkey
    @model.on 'change:selected', @render
    @render()
  render: =>
    @$el.html(if @model.get('selected') then "[#{@hotkey}]" else "")

class CommentView extends SelectableView
  initialize: (options) =>
    super
    @model.on 'change:collapsed', (model, collapsed) =>
      if collapsed then @collapse() else @show()
    @model.on 'change:hidden', (model, hidden) =>
      if hidden then @hide() else @show()

    # subview: [+/-] collapse toggle
    @$el.find('span.comhead').append(toggle_el = @make 'span', { class: 'collapse' })
    @collapse_toggle = new CollapseToggle { el: toggle_el, model: @model }

    # subview: link hotkeys
    @annotations = _.map(
      @model.get('links')
      (link, index) =>
        $link = @$el.find "td:eq(3) .comment a:eq(#{index})"
        hotkey = index + 1
        annotation_el = @make 'span',
          title: "press #{hotkey} to open link"
          class: 'keyNavAnnotation'
        $link.after annotation_el
        new KeyNavAnnotation { el: annotation_el, model: @model, hotkey: hotkey }
    )
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

selectable_things = new SelectableCollection()
# construct linked list
# (assumes that selctable things are added to the collection in order)
prev = null
selectable_things.on 'add', (model) ->
  model.set { prev: prev }
  prev?.set { next: model }
  prev = model

init_news_view = () ->
  trs = $('table:first > tbody > tr:eq(2) > td:eq(0) > table > tbody > tr')
  index = 0
  while index <= trs.length - 5
    submission_el = $(trs[index])
    submission = Submission.create submission_el
    submission_view = new SubmissionView
      el: submission_el
      model: submission
      sister_els: [ submission_el.next(), submission_el.next().next() ]
    submission_el.next().next().html "<td colspan=3></td>" # makes the highlighting show up
    selectable_things.add submission
    submission.set { selected: true } if index is 0
    index += 3

init_item_view = () ->
  # submission
  submission_el = $('table:first > tbody > tr:nth-child(3):first >
    td:first > table:eq(0) > tbody > tr:eq(0)')
  submission = Submission.create submission_el
  submission_view = new SubmissionView
    el: submission_el
    model: submission
    sister_els: submission_el.next() # also toggle selected on this el
  selectable_things.add submission

  # add comment box
  add_comment = new AddComment()
  add_comment_view = new AddCommentView
    el: $('table:first > tbody > tr:nth-child(3):first > td:first > table:eq(0) > tbody > tr:eq(3)')
    model: add_comment
  selectable_things.add add_comment

  # accumulate comments
  comment_views = []
  last_comment_at_depth = {} # map from depth to last comment seen at that depth. used to set parent
  first = null
  $('table:first > tbody > tr:nth-child(3):first > td:first > table:eq(1) > tbody > tr').each () ->
    $row = $(this)
    depth  = parseInt($row.find('img:first').attr('width')) / 40
    parent = last_comment_at_depth["#{depth-1}"]
    comment = new Comment
      user     : $row.find('a[href^="user"]').text()
      content  : $row.find('table > tbody > tr:first > td:last .comment').text()
      depth    : depth
      parent   : parent
      links    : $row.find('a[rel="nofollow"]').map () -> $(this).attr('href')
      upvote_link_id: $row.find('a[id^="up_"]').attr('id')
      downvote_link_id: $row.find('a[id^="down_"]').attr('id')
      reply_href: $row.find('a[href^="reply"]').attr('href')
    parent.get('children').push comment if parent?
    comment_view = new CommentView { el: $(this), model: comment }
    selectable_things.add comment
    first = comment.set({ selected: true }) if not first
    last_comment_at_depth["#{depth}"] = comment # next we see at depth+1 will have this asa parent

  # default to selecting submission if no comments present
  submission.set({ selected: true }) if not first

$(document).ready () ->
  if window.location.pathname is '/item'
    init_item_view()
  else if window.location.pathname in ['/', '/news']
    init_news_view()
