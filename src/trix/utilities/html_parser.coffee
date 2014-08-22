#= require trix/models/document
#= require trix/utilities/dom

class Trix.HTMLParser
  allowedAttributes = "style href src width height data-trix-identifier".split(" ")

  @parse: (html, options) ->
    parser = new this html, options
    parser.parse()
    parser

  constructor: (@html, {@attachments} = {}) ->
    @blocks = []

  createHiddenContainer: ->
    @container = sanitizeHTML(squish(@html))
    @container.style["display"] = "none"
    document.body.appendChild(@container)

  removeHiddenContainer: ->
    document.body.removeChild(@container)

  parse: ->
    @createHiddenContainer()
    walker = Trix.DOM.createTreeWalker(@container)
    @processNode(walker.currentNode) while walker.nextNode()
    @removeHiddenContainer()

  processNode: (node) ->
    @appendBlockForNode(node)
    switch node.nodeType
      when Node.TEXT_NODE
        @processTextNode(node)
      when Node.ELEMENT_NODE
        @processElementNode(node)

  appendBlockForNode: (node) ->
    if @currentBlockElement?
      unless @currentBlockElement.contains(node)
        @appendBlockForAttributes({})
        delete @currentBlockElement

    if node.nodeType is Node.ELEMENT_NODE
      if window.getComputedStyle(node).display is "block"
        switch node.tagName.toLowerCase()
          when "blockquote"
            @appendBlockForAttributes(quote: true)
            @currentBlockElement = node
          when "pre"
            @appendBlockForAttributes(code: true)
            @currentBlockElement = node

    unless @blocks.length
      @appendBlockForAttributes({})

  processTextNode: (node) ->
    string = node.textContent.replace(/\s/, " ")
    @appendStringWithAttributes(string, getAttributes(node.parentNode))

  processElementNode: (node) ->
    switch node.tagName.toLowerCase()
      when "br"
        unless nodeIsExtraBR(node)
          @appendStringWithAttributes("\n", getAttributes(node))
      when "img"
        attributes = getAttributes(node)
        attributes.url = node.getAttribute("src")
        # TODO: we lose the true content type here
        attributes.contentType = "image"
        attributes.identifier = identifier if identifier = node.getAttribute("data-trix-identifier")
        attributes[key] = value for key in ["width", "height"] when value = node.getAttribute(key)
        @appendAttachmentForAttributes(attributes)

  appendBlockForAttributes: (attributes) ->
    @text = new Trix.Text
    block = new Trix.Block @text, attributes
    @blocks.push(block)

  appendStringWithAttributes: (string, attributes) ->
    text = Trix.Text.textForStringWithAttributes(string, attributes)
    @appendText(@text.appendText(text))

  appendAttachmentForAttributes: (attributes) ->
    if managedAttachment = @findManagedAttachmentByAttributes(attributes)
      attachment = managedAttachment.attachment
    else
      attachment = new Trix.Attachment

    text = Trix.Text.textForAttachmentWithAttributes(attachment, attributes)
    @appendText(@text.appendText(text))

  appendText: (@text) ->
    index = @blocks.length - 1
    block = @blocks[index]
    @blocks[index] = block.copyWithText(@text)

  findManagedAttachmentByAttributes: (attributes) ->
    return unless @attachments
    {identifier, url} = attributes
    if identifier?
      @attachments.findWhere({identifier})
    else if url?
      @attachments.findWhere({url})

  getDocument: ->
    new Trix.Document @blocks

  getAttributes = (element) ->
    attributes = {}
    style = window.getComputedStyle(element)

    for attribute, config of Trix.attributes when config.parser
      if value = config.parser({element, style})
        attributes[attribute] = value

    attributes

  squish = (string) ->
    string.trim().replace(/\n/g, " ").replace(/\s{2,}/g, " ")

  sanitizeHTML = (html) ->
    container = document.createElement("div")
    container.innerHTML = html
    walker = Trix.DOM.createTreeWalker(container, NodeFilter.SHOW_ELEMENT)

    while walker.nextNode()
      element = walker.currentNode
      for attribute in [element.attributes...]
        do (attribute) ->
          {name} = attribute
          element.removeAttribute(name) unless name in allowedAttributes

    container

  nodeIsExtraBR = (node) ->
    node.tagName.toLowerCase() is "br" and
      node.tagName is node.previousElementSibling?.tagName and
      node is node.parentNode.lastChild and
      window.getComputedStyle(node.parentNode).display is "block"
