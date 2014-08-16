structured_types_uninitialized = require "./StructuredTypes"

module.exports = (HB)->
  structured_types = structured_types_uninitialized HB
  types = structured_types.types
  parser = structured_types.parser

  #
  # At the moment TextDelete type equals the Delete type in BasicTypes.
  # @see BasicTypes.Delete
  #
  class TextDelete extends types.Delete
  parser["TextDelete"] = parser["Delete"]

  #
  #  Extends the basic Insert type to an operation that holds a text value
  #
  class TextInsert extends types.Insert
    #
    # @param {String} content The content of this Insert-type Operation. Usually you restrict the length of content to size 1
    # @param {Object} uid A unique identifier. If uid is undefined, a new uid will be created.
    #
    constructor: (@content, uid, prev, next, origin)->
      if not (prev? and next?)
        throw new Error "You must define prev, and next for TextInsert-types!"
      super uid, prev, next, origin
    #
    # Retrieve the effective length of the $content of this operation.
    #
    getLength: ()->
      if @isDeleted()
        0
      else
        @content.length

    #
    # The result will be concatenated with the results from the other insert operations
    # in order to retrieve the content of the engine.
    # @see HistoryBuffer.toExecutedArray
    #
    val: (current_position)->
      if @isDeleted()
        ""
      else
        @content

    #
    # Convert all relevant information of this operation to the json-format.
    # This result can be send to other clients.
    #
    _encode: ()->
      json =
        {
          'type': "TextInsert"
          'content': @content
          'uid' : @getUid()
          'prev': @prev_cl.getUid()
          'next': @next_cl.getUid()
        }
      if @origin? and @origin isnt @prev_cl
        json["origin"] = @origin.getUid()
      json

  parser["TextInsert"] = (json)->
    {
      'content' : content
      'uid' : uid
      'prev': prev
      'next': next
      'origin' : origin
    } = json
    new TextInsert content, uid, prev, next, origin

  #
  # Handles a Text-like data structures with support for insertText/deleteText at a word-position.
  #
  class Word extends types.ListManager

    #
    # @param {Object} uid A unique identifier. If uid is undefined, a new uid will be created.
    #
    constructor: (uid, beginning, end, prev, next, origin)->
      super uid, beginning, end, prev, next, origin

    #
    # Inserts a string into the word
    #
    insertText: (position, content)->
      o = @getOperationByPosition position
      for c in content
        op = new TextInsert c, undefined, o.prev_cl, o
        HB.addOperation(op).execute()

    #
    # Deletes a part of the word.
    #
    deleteText: (position, length)->
      o = @getOperationByPosition position

      delete_ops = []
      for i in [0...length]
        d = HB.addOperation(new TextDelete undefined, o).execute()
        o = o.next_cl
        while o.isDeleted() and not (o instanceof types.Delimiter)
          if o instanceof types.Delimiter
            throw new Error "You can't delete more than there is.."
          o = o.next_cl
        delete_ops.push d._encode()
        if o instanceof types.Delimiter
          break


    #
    # Replace the content of this word with another one. Concurrent replacements are not merged!
    # Only one of the replacements will be used.
    #
    # Can only be used if the ReplaceManager was set!
    # @see Word.setReplaceManager
    #
    replaceText: (text)->
      if @replace_manager?
        word = HB.addOperation(new Word undefined).execute()
        word.insertText 0, text
        @replace_manager.replace(word)
      else
        throw new Error "This type is currently not maintained by a ReplaceManager!"

    #
    # @returns [Json] A Json object.
    #
    val: ()->
      c = for o in @toArray()
        if o.val?
          o.val()
        else
          ""
      c.join('')

    #
    # In most cases you would embed a Word in a Replaceable, wich is handled by the ReplaceManager in order
    # to provide replace functionality.
    #
    setReplaceManager: (op)->
      @saveOperation 'replace_manager', op
      @validateSavedOperations

    #
    # Bind this Word to a textfield.
    #
    bind: (textfield)->
      word = @
      textfield.value = @val()

      @on "insert", (event, op)->
        if op.creator isnt HB.getUserId()
          o_pos = op.getPosition()
          fix = (cursor)->
            if cursor <= o_pos
              cursor
            else
              cursor += 1
              cursor
          left = fix textfield.selectionStart
          right = fix textfield.selectionEnd

          textfield.value = word.val()
          textfield.setSelectionRange left, right


      @on "delete", (event, op)->
        o_pos = op.getPosition()
        fix = (cursor)->
          if cursor < o_pos
            cursor
          else
            cursor -= 1
            cursor
        left = fix textfield.selectionStart
        right = fix textfield.selectionEnd

        textfield.value = word.val()
        textfield.setSelectionRange left, right

      # consume all text-insert changes.
      textfield.onkeypress = (event)->
        char = String.fromCharCode event.keyCode
        if char.length > 0
          pos = Math.min textfield.selectionStart, textfield.selectionEnd
          diff = Math.abs(textfield.selectionEnd - textfield.selectionStart)
          word.deleteText pos, diff
          word.insertText pos, char
        else
          event.preventDefault()

      #
      # consume deletes. Note that
      #   chrome: won't consume deletions on keypress event.
      #   keyCode is deprecated. BUT: I don't see another way.
      #     since event.key is not implemented in the current version of chrome.
      #     Every browser supports keyCode. Let's stick with it for now..
      #
      textfield.onkeydown = (event)->
        pos = Math.min textfield.selectionStart, textfield.selectionEnd
        diff = Math.abs(textfield.selectionEnd - textfield.selectionStart)
        if event.keyCode? and event.keyCode is 8
          if diff > 0
            word.deleteText pos, diff
          else
            if event.ctrlKey? and event.ctrlKey
              val = textfield.value
              new_pos = pos
              del_length = 0
              if pos > 0
                new_pos--
                del_length++
              while new_pos > 0 and val[new_pos] isnt " " and val[new_pos] isnt '\n'
                new_pos--
                del_length++
              word.deleteText new_pos, (pos-new_pos)
              textfield.setSelectionRange new_pos, new_pos
            else
              word.deleteText (pos-1), 1
          event.preventDefault()
        else if event.keyCode? and event.keyCode is 46
          if diff > 0
            word.deleteText pos, diff
          else
            word.deleteText pos, 1
          event.preventDefault()



    #
    # Encode this operation in such a way that it can be parsed by remote peers.
    #
    _encode: ()->
      json = {
        'type': "Word"
        'uid' : @getUid()
        'beginning' : @beginning.getUid()
        'end' : @end.getUid()
      }
      if @prev_cl?
        json['prev'] = @prev_cl.getUid()
      if @next_cl?
        json['next'] = @next_cl.getUid()
      if @origin? and @origin isnt @prev_cl
        json["origin"] = @origin.getUid()
      json

  parser['Word'] = (json)->
    {
      'uid' : uid
      'beginning' : beginning
      'end' : end
      'prev': prev
      'next': next
      'origin' : origin
    } = json
    new Word uid, beginning, end, prev, next, origin

  types['TextInsert'] = TextInsert
  types['TextDelete'] = TextDelete
  types['Word'] = Word
  structured_types


