//
//  DBManager.swift
//  MonkeyChat
//
//  Created by Gianni Carlo on 5/31/16.
//  Copyright © 2016 Criptext. All rights reserved.
//

import Foundation
import MonkeyKit
import RealmSwift

class DBManager {
  
  class func deleteAll(){
    let realm = try! Realm()
    try! realm.write {
      realm.deleteAll()
    }
  }
  
  class func store(_ message:MOKMessage) {
    
    if(message.messageId == ""){
      return
    }
    
    let messageItem = DBManager.transform(message)
    let realm = try! Realm()
    
    try! realm.write {
      realm.add(messageItem, update: true)
    }
    
  }
    
  class func transform(_ message:MOKMessage) -> MessageItem {
    
    let messageItem = MessageItem()
    messageItem.messageId = message.messageId
    messageItem.oldMessageId = message.oldMessageId!
    messageItem.sender = message.sender
    messageItem.recipient = message.recipient
    messageItem.timestampOrder = message.timestampOrder
    messageItem.timestampCreated = message.timestampCreated
    messageItem.plainText = message.plainText
    messageItem.encryptedText = message.encryptedText
    if let params = message.params {
      messageItem.params = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
    }
    messageItem.props = try? JSONSerialization.data(withJSONObject: message.props, options: .prettyPrinted)
    
    return messageItem
  }
    
  class func transform(_ messageItem:MessageItem) -> MOKMessage {
    
    var props = [AnyHashable: Any]()
    var params = [AnyHashable: Any]()
  
    if let bytesParams = messageItem.params {
      params = try! JSONSerialization.jsonObject(with: bytesParams, options: .mutableContainers) as! [AnyHashable : Any]
    }
    if let bytesProps = messageItem.props {
      props = try! JSONSerialization.jsonObject(with: bytesProps, options: .mutableContainers) as! [AnyHashable: Any]
    }

    let message = MOKMessage(message: messageItem.plainText, sender: messageItem.sender, recipient: messageItem.recipient, params: params, props: props)
    message.messageId = messageItem.messageId
    message.oldMessageId = messageItem.oldMessageId
    message.timestampOrder = messageItem.timestampOrder
    message.timestampCreated = messageItem.timestampCreated
    message.encryptedText = messageItem.encryptedText
    
    return message
  }

  class func getMessage(_ id:String) -> MOKMessage? {
    let realm = try! Realm()
    
    if let messageItem = realm.object(ofType: MessageItem.self, forPrimaryKey: id) {
      return DBManager.transform(messageItem)
    }
    
    return nil
  }
  
  class func getMessages(_ sender:String, recipient:String, from:MOKMessage?, count:Int) -> [MOKMessage]{
    let realm = try! Realm()
    
    let condition = "((sender == %@ AND recipient == %@) OR" + (recipient.contains("G:") ? "(sender != %@ AND recipient == %@))" : "(recipient == %@ AND sender == %@))")
    let predicate = NSPredicate(format: "\(condition) AND timestampCreated < \(floor(from?.timestampCreated ?? 0))", sender, recipient, sender, recipient)
    let results = realm.objects(MessageItem.self).filter(predicate).sorted(byProperty: "timestampCreated", ascending: false)
    
    var messages = [MOKMessage]()
    
    for (index, messageItem) in results.enumerated() {
      if count <= index {
        break
      }
      
      guard let msg = from , msg.messageId != messageItem.messageId && messageItem.timestampCreated < msg.timestampCreated else {
        continue
      }
      
      let message = DBManager.transform(messageItem)
      messages.insert(message, at: 0)
    }
    return messages
  }
  
  class func exists(_ message:MOKMessage) -> Bool {
    let realm = try! Realm()
      
    let results = realm.objects(MessageItem.self).filter("messageId = \(message.messageId) OR messageId = \(message.oldMessageId)")
    
    return results.count > 0
  }
  
  class func existsMessage(_ id:String, oldId:String) -> Bool {
    let realm = try! Realm()
    
    let results = realm.objects(MessageItem.self).filter("messageId == %@ OR messageId == %@", id, oldId)
    
    return results.count > 0
  }
  
  class func updateMessage(_ id:String, oldId:String, conversation: MOKConversation?) {
    let realm = try! Realm()
    guard let message = realm.object(ofType: MessageItem.self, forPrimaryKey: oldId) else {
      return
    }
    let newMessage = MessageItem()
    newMessage.messageId = id
    newMessage.oldMessageId = oldId
    newMessage.sender = message.sender
    newMessage.recipient = message.recipient
    newMessage.plainText = message.plainText
    newMessage.encryptedText = message.encryptedText
    newMessage.timestampOrder = message.timestampOrder
    newMessage.timestampCreated = message.timestampCreated
    newMessage.props = message.props
    newMessage.params = message.params
    
    try! realm.write {
      realm.delete(message)
      realm.add(newMessage, update: true)
      
      guard let mokconv = conversation, let conv = realm.object(ofType: ConversationItem.self, forPrimaryKey: mokconv.conversationId) else {
        return
      }
      conv.lastMessage = newMessage
      realm.add(conv, update: true)
    }
  }
}

extension DBManager {
  
  class func store(_ user:MOKUser){
    let realm = try! Realm()
    
    try! realm.write {
      
      let userDB = User()
      userDB.monkeyId = user.monkeyId
      
      let infoList = List<SimpleInfo>()
      for info in user.info! {
        let simple = SimpleInfo()
        simple.key = info.key as! String
        simple.value = info.value as! String
        infoList.append(simple)
      }
      
      userDB.info = infoList
      realm.add(userDB, update: true)
    }
  }
  
  class func store(_ users:[MOKUser]){
    let realm = try! Realm()
    
    try! realm.write {
      for user in users {
        let userDB = User()
        userDB.monkeyId = user.monkeyId
        
        let infoList = List<SimpleInfo>()
        for info in user.info! {
          let simple = SimpleInfo()
          simple.key = info.key as! String
          simple.value = info.value as! String
          infoList.append(simple)
        }
        
        userDB.info = infoList
        realm.add(userDB, update: true)
      }
    }
  }
  
  class func getUser(_ id:String) -> MOKUser? {
    return DBManager.getUsers([id]).first
  }
    
  class func getUsers(_ ids:[String]) -> [MOKUser]{
    let realm = try! Realm()
    
    let results = realm.objects(User.self).filter("monkeyId IN %@", ids)
    
    var arrayUser = [MOKUser]()
    for userdb in results {
      let user = MOKUser(id: userdb.monkeyId)
      user.info = [:]
      
      for simpleInfo:SimpleInfo in userdb.info {
        user.info![simpleInfo.key] = simpleInfo.value
      }
      
      arrayUser.append(user)
    }
    
    return arrayUser
  }
    
  class func monkeyIdsNotStored(_ ids:Set<String>) -> [String]{
    let realm = try! Realm()
    
    //search among stored users
    let results = realm.objects(User.self).filter("monkeyId IN %@", ids)
    
    //monkey ids found
    if let monkeyIds = results.value(forKey: "monkeyId") as? [String] {
//    let realIds = Set(ids.allObjects as! [String])
      return Array(ids.subtracting(monkeyIds))
    }
    
    return []
  }
  
}

extension DBManager {
  
  class func store(_ conversation:MOKConversation) {
    let conversationItem = DBManager.transform(conversation)
    let realm = try! Realm()
    
    try! realm.write {
      realm.add(conversationItem, update: true)
    }
  }
  
  class func transform(_ conversation:MOKConversation) -> ConversationItem {
    let conversationItem = ConversationItem()
    conversationItem.conversationId = conversation.conversationId
    conversationItem.info = try? JSONSerialization.data(withJSONObject: conversation.info, options: .prettyPrinted)
    conversationItem.members = conversation.members.componentsJoined(by: ",")
    if let lastMessage = conversation.lastMessage {
      conversationItem.lastMessage = DBManager.transform(lastMessage)
    }
    conversationItem.unread = Int32(conversation.unread)
    conversationItem.lastModified = conversation.lastModified
    conversationItem.lastSeen = conversation.lastSeen
    conversationItem.lastRead = conversation.lastRead
    
    return conversationItem
  }
  
  class func transform(_ conversationItem:ConversationItem) -> MOKConversation {
    var info = NSMutableDictionary()
    if let bytesInfo = conversationItem.info {
      info = try! JSONSerialization.jsonObject(with: bytesInfo, options: .mutableContainers) as! NSMutableDictionary
    }

    let conversation = MOKConversation(id: conversationItem.conversationId)
    conversation.members = NSMutableArray(array: conversationItem.members.components(separatedBy: ","))
    conversation.info = info
    if let messageItem = conversationItem.lastMessage {
      conversation.lastMessage = DBManager.transform(messageItem)
    }
    conversation.unread = conversationItem.unread
    conversation.lastModified = conversationItem.lastModified
    conversation.lastSeen = conversationItem.lastSeen
    conversation.lastRead = conversationItem.lastRead
    
    return conversation
  }
  
  class func getConversation(_ id:String) -> MOKConversation? {
    let realm = try! Realm()
    
    if let conversationItem = realm.object(ofType: ConversationItem.self, forPrimaryKey: id){
      return DBManager.transform(conversationItem)
    }
    
    return nil
  }
  
  class func getConversations(_ from:MOKConversation?, count:Int) -> [MOKConversation] {
    let realm = try! Realm()
    
    var predicate = NSPredicate(format: "lastModified > 0")
    if let conv = from {
      predicate = NSPredicate(format: "lastModified < \(conv.lastModified)")
    }
    let results = realm.objects(ConversationItem.self).filter(predicate).sorted(byProperty: "lastModified", ascending: false)
    
    var conversations = [MOKConversation]()
    for (index, conversationItem) in results.enumerated() {
      if count <= index {
        break
      }
      
      if let conversation = from {
        if conversation.conversationId == conversationItem.conversationId && conversationItem.lastModified <= conversation.lastModified {
          continue
        }
      }
      
      conversations.insert(DBManager.transform(conversationItem), at: 0)
    }
    return conversations.reversed()
  }
  
  class func delete(_ conversation:MOKConversation) {
    let realm = try! Realm()
    
    if let conversationItem = realm.object(ofType: ConversationItem.self, forPrimaryKey: conversation.conversationId){
      try! realm.write {
        realm.delete(conversationItem)
      }
    }
  }
  
}
