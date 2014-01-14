#= require spec_helper

describe 'Models.Board', ->
  subject = null

  beforeEach ->
    subject = new Whiteboard7.Models.Board

  it 'should create subject', ->
    pp subject
    expect(subject).to.exist

  it '#urlRoot', ->
    subject.urlRoot.should.eql "/boards"

  it '#addBoardMember', (done)->
    subject.set 'board_members', []

    subject.on 'change:board_members', -> done()

    subject.addBoardMember({ id: 1 })
    subject.get('board_members').should.eql [{ id: 1 }]

  it '#removeBoardMember', (done)->
    subject.set 'board_members', [{ id: 1 }, { id: 2 }]

    subject.on 'change:board_members', -> done()

    subject.removeBoardMember(1)
    subject.get('board_members').should.eql [{ id: 2 }]

  it '#isBoardMember', ()->
    subject.set 'board_members', [{ id: 1 }, { id: 2 }]
    subject.isBoardMember({ id: 1 }).should.be.true
    subject.isBoardMember({ id: 3 }).should.be.false
