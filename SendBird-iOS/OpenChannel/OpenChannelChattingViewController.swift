//
//  OpenChannelChattingViewController.swift
//  SendBird-iOS
//
//  Created by Jed Kyung on 10/13/16.
//  Copyright © 2016 SendBird. All rights reserved.
//

import UIKit
import SendBirdSDK
import AVKit
import AVFoundation
import MobileCoreServices
import Photos

class OpenChannelChattingViewController: UIViewController, SBDConnectionDelegate, SBDChannelDelegate, ChattingViewDelegate, MessageDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var openChannel: SBDOpenChannel!
    
    @IBOutlet weak var chattingView: ChattingView!
    @IBOutlet weak var navItem: UINavigationItem!
    @IBOutlet weak var bottomMargin: NSLayoutConstraint!

    private var messageQuery: SBDPreviousMessageListQuery!
    private var delegateIdentifier: String!
    private var hasNext: Bool = true
    private var refreshInViewDidAppear: Bool = true
    private var isLoading: Bool = false
    private var keyboardShown: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let titleView: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width - 100, height: 64))
        titleView.attributedText = Utils.generateNavigationTitle(mainTitle: String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount), subTitle: "")
        titleView.numberOfLines = 2
        titleView.textAlignment = NSTextAlignment.center
        
        let titleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(clickReconnect))
        titleView.isUserInteractionEnabled = true
        titleView.addGestureRecognizer(titleTapRecognizer)
        
        self.navItem.titleView = titleView
        
        let negativeLeftSpacer = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.fixedSpace, target: nil, action: nil)
        negativeLeftSpacer.width = -2
        let negativeRightSpacer = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.fixedSpace, target: nil, action: nil)
        negativeRightSpacer.width = -2
        
        let leftCloseItem = UIBarButtonItem(image: UIImage(named: "btn_close"), style: UIBarButtonItemStyle.done, target: self, action: #selector(close))
        let rightOpenMoreMenuItem = UIBarButtonItem(image: UIImage(named: "btn_more"), style: UIBarButtonItemStyle.done, target: self, action: #selector(openMoreMenu))
        
        self.navItem.leftBarButtonItems = [negativeLeftSpacer, leftCloseItem]
        self.navItem.rightBarButtonItems = [negativeRightSpacer, rightOpenMoreMenuItem]
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(notification:)), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide(notification:)), name: NSNotification.Name.UIKeyboardDidHide, object: nil)
        
        self.delegateIdentifier = self.description
        SBDMain.add(self as SBDChannelDelegate, identifier: self.delegateIdentifier)
        SBDMain.add(self as SBDConnectionDelegate, identifier: self.delegateIdentifier)
        
        self.chattingView.fileAttachButton.addTarget(self, action: #selector(sendFileMessage), for: UIControlEvents.touchUpInside)
        self.chattingView.sendButton.addTarget(self, action: #selector(sendMessage), for: UIControlEvents.touchUpInside)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.refreshInViewDidAppear {
            self.chattingView.initChattingView()
            self.chattingView.delegate = self
            
            self.loadPreviousMessage(initial: true)
        }
        
        self.refreshInViewDidAppear = true
    }

    func keyboardDidShow(notification: Notification) {
        self.keyboardShown = true
        let keyboardInfo = notification.userInfo
        let keyboardFrameBegin = keyboardInfo?[UIKeyboardFrameEndUserInfoKey]
        let keyboardFrameBeginRect = (keyboardFrameBegin as! NSValue).cgRectValue
        DispatchQueue.main.async {
            self.bottomMargin.constant = keyboardFrameBeginRect.size.height
            self.view.layoutIfNeeded()
            self.chattingView.stopMeasuringVelocity = true
            self.chattingView.scrollToBottom(animated: true, force: false)
        }
    }
    
    func keyboardDidHide(notification: Notification) {
        self.keyboardShown = false
        DispatchQueue.main.async {
            self.bottomMargin.constant = 0
            self.view.layoutIfNeeded()
            self.chattingView.scrollToBottom(animated: true, force: false)
        }
    }
    
    @objc private func close() {
        self.openChannel.exitChannel { (error) in
            self.dismiss(animated: false) {
                
            }
        }
    }
    
    @objc private func openMoreMenu() {
        let vc = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        let seeParticipantListAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "SeeParticipantListButton"), style: UIAlertActionStyle.default) { (action) in
            DispatchQueue.main.async {
                let plvc = ParticipantListViewController(nibName: "ParticipantListViewController", bundle: Bundle.main)
                plvc.channel = self.openChannel
                self.refreshInViewDidAppear = false
                self.present(plvc, animated: false, completion: nil)
            }
        }
        let seeBlockedUserListAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "SeeBlockedUserListButton"), style: UIAlertActionStyle.default) { (action) in
            DispatchQueue.main.async {
                let blvc = BlockedUserListViewController(nibName: "BlockedUserListViewController", bundle: Bundle.main)
                self.refreshInViewDidAppear = false
                self.present(blvc, animated: false, completion: nil)
            }
        }
        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
        vc.addAction(seeParticipantListAction)
        vc.addAction(seeBlockedUserListAction)
        vc.addAction(closeAction)
        
        self.present(vc, animated: true, completion: nil)
    }
    
    private func loadPreviousMessage(initial: Bool) {
        if initial == true {
            self.chattingView.resendableFileData.removeAll()
            self.chattingView.resendableMessages.removeAll()
            self.chattingView.preSendFileData.removeAll()
            self.chattingView.preSendMessages.removeAll()
            
            self.chattingView.chattingTableView.isHidden = true
            self.messageQuery = self.openChannel.createPreviousMessageListQuery()
            self.hasNext = true
            self.chattingView.messages.removeAll()
            DispatchQueue.main.async {
                self.chattingView.chattingTableView.reloadData()
            }
        }
        
        if self.hasNext == false {
            self.chattingView.chattingTableView.isHidden = false
            return
        }
        
        if self.isLoading == true {
            self.chattingView.chattingTableView.isHidden = false
            return
        }
        
        self.isLoading = true
        
        self.messageQuery.loadPreviousMessages(withLimit: 30, reverse: !initial) { (messages, error) in
            if error != nil {
                let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                vc.addAction(closeAction)
                DispatchQueue.main.async {
                    self.present(vc, animated: true, completion: nil)
                }
                
                self.chattingView.chattingTableView.isHidden = false
                self.isLoading = false
                
                return
            }
            
            if messages?.count == 0 {
                self.hasNext = false
            }
            
            if initial == true {
                for message in messages! {
                    self.chattingView.messages.append(message)
                }
            }
            else {
                for message in messages! {
                    self.chattingView.messages.insert(message, at: 0)
                }
            }
            
            if initial == true {
                self.chattingView.initialLoading = true
                
                DispatchQueue.main.async {
                    self.chattingView.chattingTableView.reloadData()
                    DispatchQueue.main.async {
                        self.chattingView.scrollToBottom(animated: false, force: true)
                        self.chattingView.chattingTableView.isHidden = false
                    }
                }
                
                self.chattingView.initialLoading = false
                self.isLoading = false
            }
            else {
                if (messages?.count)! > 0 {
                    DispatchQueue.main.async {
                        self.chattingView.chattingTableView.reloadData()
                        DispatchQueue.main.async {
                            self.chattingView.scrollToPosition(position: (messages?.count)! - 1)
                        }
                    }
                }
                self.isLoading = false
            }
        }
    }
    
    @objc private func sendMessage() {
        if self.chattingView.messageTextView.text.characters.count > 0 {
            let message = self.chattingView.messageTextView.text
            self.chattingView.messageTextView.text = ""
            
            let preSendMessage = self.openChannel.sendUserMessage(message, data: "", customType: "", targetLanguages: [], completionHandler: { (userMessage, error) in
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(150), execute: {
                    let preSendMessage = self.chattingView.preSendMessages[(userMessage?.requestId)!] as! SBDUserMessage
                    self.chattingView.preSendMessages.removeValue(forKey: (userMessage?.requestId)!)
                    
                    if error != nil {
                        self.chattingView.resendableMessages[(userMessage?.requestId)!] = userMessage
                        self.chattingView.chattingTableView.reloadData()
                        DispatchQueue.main.async {
                            self.chattingView.scrollToBottom(animated: true, force: true)
                        }
                        
                        return
                    }
                    
                    self.chattingView.messages[self.chattingView.messages.index(of: preSendMessage)!] = userMessage!
                    
                    self.chattingView.chattingTableView.reloadData()
                    DispatchQueue.main.async {
                        self.chattingView.scrollToBottom(animated: true, force: true)
                    }
                })
            })
            self.chattingView.preSendMessages[preSendMessage.requestId!] = preSendMessage
            self.chattingView.messages.append(preSendMessage)
            self.chattingView.chattingTableView.reloadData()
            DispatchQueue.main.async {
                self.chattingView.scrollToBottom(animated: true, force: true)
            }
        }
    }
    
    @objc private func sendFileMessage() {
        let mediaUI = UIImagePickerController()
        mediaUI.sourceType = UIImagePickerControllerSourceType.photoLibrary
        let mediaTypes = [String(kUTTypeImage), String(kUTTypeMovie)]
        mediaUI.mediaTypes = mediaTypes
        mediaUI.delegate = self
        self.refreshInViewDidAppear = false
        self.present(mediaUI, animated: true, completion: nil)
    }
    
    func clickReconnect() {
        if SBDMain.getConnectState() != SBDWebSocketConnectionState.SBDWebSocketOpen && SBDMain.getConnectState() != SBDWebSocketConnectionState.SBDWebSocketConnecting {
            SBDMain.reconnect()
        }
    }
    
    // MARK: SBDConnectionDelegate
    func didStartReconnection() {
        if self.navItem.titleView != nil && self.navItem.titleView is UILabel {
            (self.navItem.titleView as! UILabel).attributedText = Utils.generateNavigationTitle(mainTitle: String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount), subTitle: Bundle.sbLocalizedStringForKey(key: "ReconnectingSubTitle"))
        }
    }
    
    func didSucceedReconnection() {
        self.loadPreviousMessage(initial: true)
        if self.navItem.titleView != nil && self.navItem.titleView is UILabel {
            (self.navItem.titleView as! UILabel).attributedText = Utils.generateNavigationTitle(mainTitle: String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount), subTitle: Bundle.sbLocalizedStringForKey(key: "ReconnectedSubTitle"))
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
            if self.navItem.titleView != nil && self.navItem.titleView is UILabel {
                (self.navItem.titleView as! UILabel).attributedText = Utils.generateNavigationTitle(mainTitle: String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount), subTitle: "")
            }
        }
    }
    
    func didFailReconnection() {
        if self.navItem.titleView != nil && self.navItem.titleView is UILabel {
            (self.navItem.titleView as! UILabel).attributedText = Utils.generateNavigationTitle(mainTitle: String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount), subTitle: Bundle.sbLocalizedStringForKey(key: "ReconnectionFailedSubTitle"))
        }
    }
    
    // MARK: SBDChannelDelegate
    func channel(_ sender: SBDBaseChannel, didReceive message: SBDBaseMessage) {
        if sender == self.openChannel {
            self.chattingView.messages.append(message)
            self.chattingView.chattingTableView.reloadData()
            DispatchQueue.main.async {
                self.chattingView.scrollToBottom(animated: true, force: false)
            }
        }
    }

    func channelWasChanged(_ sender: SBDBaseChannel) {
        if sender == self.openChannel {
            DispatchQueue.main.async {
                self.navItem.title = String(format: "%@(%ld)", self.openChannel.name, self.openChannel.participantCount)
            }
        }
    }
    
    func channelWasDeleted(_ channelUrl: String, channelType: SBDChannelType) {
        let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ChannelDeletedTitle"), message: Bundle.sbLocalizedStringForKey(key: "ChannelDeletedMessage"), preferredStyle: UIAlertControllerStyle.alert)
        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel) { (action) in
            self.close()
        }
        vc.addAction(closeAction)
        DispatchQueue.main.async {
            self.present(vc, animated: true, completion: nil)
        }
    }
    
    func channel(_ sender: SBDBaseChannel, messageWasDeleted messageId: Int64) {
        if sender == self.openChannel {
            for message in self.chattingView.messages {
                if message.messageId == messageId {
                    self.chattingView.messages.remove(at: self.chattingView.messages.index(of: message)!)
                    DispatchQueue.main.async {
                        self.chattingView.chattingTableView.reloadData()
                    }
                    break
                }
            }
        }
    }
    
    // MARK: ChattingViewDelegate
    func loadMoreMessage(view: UIView) {
        self.loadPreviousMessage(initial: false)
    }
    
    func startTyping(view: UIView) {

    }
    
    func endTyping(view: UIView) {

    }
    
    func hideKeyboardWhenFastScrolling(view: UIView) {
        DispatchQueue.main.async {
            self.bottomMargin.constant = 0
            self.view.layoutIfNeeded()
            self.chattingView.scrollToBottom(animated: true, force: false)
        }
        self.view.endEditing(true)
    }
    
    // MARK: MessageDelegate
    func clickProfileImage(viewCell: UITableViewCell, user: SBDUser) {
        let alert = UIAlertController(title: user.nickname, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        let startDistinctGroupChannel = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "OpenDistinctGroupChannel"), style: UIAlertActionStyle.default) { (action) in
            SBDGroupChannel.createChannel(with: [user], isDistinct: true, completionHandler: { (channel, error) in
                if error != nil {
                    DispatchQueue.main.async {
                        let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                        vc.addAction(closeAction)
                        DispatchQueue.main.async {
                            self.present(vc, animated: true, completion: nil)
                        }
                    }
                    
                    return
                }
                
                DispatchQueue.main.async {
                    let vc = GroupChannelChattingViewController(nibName: "GroupChannelChattingViewController", bundle: Bundle.main)
                    vc.groupChannel = channel
                    self.present(vc, animated: false, completion: nil)
                }
            })
        }
        let startNonDistinctGroupChannel = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "OpenNonDistinctGroupChannel"), style: UIAlertActionStyle.default) { (action) in
            SBDGroupChannel.createChannel(with: [user], isDistinct: false, completionHandler: { (channel, error) in
                if error != nil {
                    DispatchQueue.main.async {
                        let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                        vc.addAction(closeAction)
                        DispatchQueue.main.async {
                            self.present(vc, animated: true, completion: nil)
                        }
                    }
                    
                    return
                }
                
                DispatchQueue.main.async {
                    let vc = GroupChannelChattingViewController(nibName: "GroupChannelChattingViewController", bundle: Bundle.main)
                    vc.groupChannel = channel
                    self.present(vc, animated: false, completion: nil)
                }
            })
        }
        let blockUserAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "BlockUserButton"), style: UIAlertActionStyle.default) { (action) in
            SBDMain.blockUser(user, completionHandler: { (blockedUser, error) in
                if error != nil {
                    DispatchQueue.main.async {
                        let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                        vc.addAction(closeAction)
                        DispatchQueue.main.async {
                            self.present(vc, animated: true, completion: nil)
                        }
                    }
                    
                    return
                }
                
                DispatchQueue.main.async {
                    let vc = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "UserBlockedTitle"), message: String(format: Bundle.sbLocalizedStringForKey(key: "UserBlockedMessage"), user.nickname!), preferredStyle: UIAlertControllerStyle.alert)
                    let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                    vc.addAction(closeAction)
                    DispatchQueue.main.async {
                        self.present(vc, animated: true, completion: nil)
                    }
                }
            })
        }
        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
        alert.addAction(startDistinctGroupChannel)
        alert.addAction(startNonDistinctGroupChannel)
        alert.addAction(blockUserAction)
        alert.addAction(closeAction)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func clickMessage(view: UIView, message: SBDBaseMessage) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
        var deleteMessageAction: UIAlertAction?
        var openFileAction: UIAlertAction?
        var openURLsAction: [UIAlertAction] = []

        if message is SBDUserMessage {
            let sender = (message as! SBDUserMessage).sender
            if sender?.userId == SBDMain.getCurrentUser()?.userId {
                deleteMessageAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "DeleteMessageButton"), style: UIAlertActionStyle.destructive, handler: { (action) in
                    self.openChannel.delete(message, completionHandler: { (error) in
                        if error != nil {
                            let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                            let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                            alert.addAction(closeAction)
                            DispatchQueue.main.async {
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    })
                })
            }
            
            do {
                let detector: NSDataDetector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let matches = detector.matches(in: (message as! SBDUserMessage).message!, options: [], range: NSMakeRange(0, ((message as! SBDUserMessage).message?.characters.count)!))
                for match in matches as [NSTextCheckingResult] {
                    let url: URL = match.url! as URL
                    let openURLAction = UIAlertAction(title: url.relativeString, style: UIAlertActionStyle.default, handler: { (action) in
                        self.refreshInViewDidAppear = false
                        UIApplication.shared.openURL(url)
                    })
                    openURLsAction.append(openURLAction)
                }
            }
            catch {
                
            }
        }
        else if message is SBDFileMessage {
            let fileMessage: SBDFileMessage = message as! SBDFileMessage
            let sender = fileMessage.sender
            let type = fileMessage.type
            let url = fileMessage.url
            
            if sender?.userId == SBDMain.getCurrentUser()?.userId {
                deleteMessageAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "DeleteMessageButton"), style: UIAlertActionStyle.destructive, handler: { (action) in
                    self.openChannel.delete(fileMessage, completionHandler: { (error) in
                        if error != nil {
                            let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                            let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                            alert.addAction(closeAction)
                            DispatchQueue.main.async {
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    })
                })
            }
            
            if type.hasPrefix("video") {
                openFileAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "PlayVideoButton"), style: UIAlertActionStyle.default, handler: { (action) in
                    let videoUrl = NSURL(string: url)
                    let player = AVPlayer(url: (videoUrl! as URL))
                    let vc = AVPlayerViewController()
                    vc.player = player
                    self.refreshInViewDidAppear = false
                    self.present(vc, animated: true, completion: {
                        player.play()
                    })
                })
            }
            else if type.hasPrefix("audio") {
                openFileAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "PlayAudioButton"), style: UIAlertActionStyle.default, handler: { (action) in
                    let audioUrl = NSURL(string: url)
                    let player = AVPlayer(url: audioUrl! as URL)
                    let vc = AVPlayerViewController()
                    vc.player = player
                    self.refreshInViewDidAppear = false
                    self.present(vc, animated: true, completion: {
                        player.play()
                    })
                })
            }
            else if type.hasPrefix("image") {
                openFileAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "OpenImageButton"), style: UIAlertActionStyle.default, handler: { (action) in
                    let imageUrl = NSURL(string: url)
                    self.refreshInViewDidAppear = false
                    UIApplication.shared.openURL(imageUrl! as URL)
                })
            }
            else {
                // TODO: Download file. Is this possible on iOS?
            }
        }
        else if message is SBDAdminMessage {
            return
        }
        
        alert.addAction(closeAction)
        if openFileAction != nil {
            alert.addAction(openFileAction!)
        }
        
        if openURLsAction.count > 0 {
            for action in openURLsAction {
                alert.addAction(action)
            }
        }
        
        if deleteMessageAction != nil {
            alert.addAction(deleteMessageAction!)
        }
        
        if openFileAction != nil || openURLsAction.count > 0 || deleteMessageAction != nil {
            DispatchQueue.main.async {
                self.refreshInViewDidAppear = false
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    func clickResend(view: UIView, message: SBDBaseMessage) {
        if message is SBDUserMessage {
            let resendableUserMessage = message as! SBDUserMessage
            var targetLanguages:[String] = []
            if resendableUserMessage.translations != nil {
                targetLanguages = Array(resendableUserMessage.translations!.keys) as! [String]
            }
            
            let preSendMessage = self.openChannel.sendUserMessage(resendableUserMessage.message, data: resendableUserMessage.data, customType: resendableUserMessage.customType, targetLanguages: targetLanguages, completionHandler: { (userMessage, error) in
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(150), execute: {
                    DispatchQueue.main.async {
                        let preSendMessage = self.chattingView.preSendMessages[(userMessage?.requestId)!]
                        self.chattingView.preSendMessages.removeValue(forKey: (userMessage?.requestId)!)
                        
                        if error != nil {
                            self.chattingView.resendableMessages[(userMessage?.requestId)!] = userMessage
                            self.chattingView.chattingTableView.reloadData()
                            DispatchQueue.main.async {
                                self.chattingView.scrollToBottom(animated: true, force: true)
                            }
                            
                            let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                            let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                            alert.addAction(closeAction)
                            DispatchQueue.main.async {
                                self.present(alert, animated: true, completion: nil)
                            }
                            
                            return
                        }
                        
                        if preSendMessage != nil {
                            self.chattingView.messages.remove(at: self.chattingView.messages.index(of: (preSendMessage! as SBDBaseMessage))!)
                            self.chattingView.messages.append(userMessage!)
                        }
                        
                        self.chattingView.chattingTableView.reloadData()
                        DispatchQueue.main.async {
                            self.chattingView.scrollToBottom(animated: true, force: true)
                        }
                    }
                })
            })
            self.chattingView.messages[self.chattingView.messages.index(of: resendableUserMessage)!] = preSendMessage
            self.chattingView.preSendMessages[preSendMessage.requestId!] = preSendMessage
            self.chattingView.chattingTableView.reloadData()
            DispatchQueue.main.async {
                self.chattingView.scrollToBottom(animated: true, force: true)
            }
        }
        else if message is SBDFileMessage {
            let resendableFileMessage = message as! SBDFileMessage
            
            var thumbnailSizes: [SBDThumbnailSize] = []
            for thumbnail in resendableFileMessage.thumbnails! as [SBDThumbnail] {
                thumbnailSizes.append(SBDThumbnailSize.make(withMaxCGSize: thumbnail.maxSize)!)
            }
            let preSendMessage = self.openChannel.sendFileMessage(withBinaryData: self.chattingView.preSendFileData[resendableFileMessage.requestId!]?["data"] as! Data, filename: resendableFileMessage.name, type: resendableFileMessage.type, size: resendableFileMessage.size, thumbnailSizes: thumbnailSizes, data: resendableFileMessage.data, customType: resendableFileMessage.customType, progressHandler: nil, completionHandler: { (fileMessage, error) in
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(150), execute: {
                    let preSendMessage = self.chattingView.preSendMessages[(fileMessage?.requestId)!]
                    self.chattingView.preSendMessages.removeValue(forKey: (fileMessage?.requestId)!)
                    
                    if error != nil {
                        self.chattingView.resendableMessages[(fileMessage?.requestId)!] = fileMessage
                        self.chattingView.resendableFileData[(fileMessage?.requestId)!] = self.chattingView.resendableFileData[resendableFileMessage.requestId!]
                        self.chattingView.resendableFileData.removeValue(forKey: resendableFileMessage.requestId!)
                        self.chattingView.chattingTableView.reloadData()
                        DispatchQueue.main.async {
                            self.chattingView.scrollToBottom(animated: true, force: true)
                        }
                        
                        let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                        let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                        alert.addAction(closeAction)
                        DispatchQueue.main.async {
                            self.present(alert, animated: true, completion: nil)
                        }
                        
                        return
                    }
                    
                    if preSendMessage != nil {
                        self.chattingView.messages.remove(at: self.chattingView.messages.index(of: (preSendMessage! as SBDBaseMessage))!)
                        self.chattingView.messages.append(fileMessage!)
                    }
                    
                    self.chattingView.chattingTableView.reloadData()
                    DispatchQueue.main.async {
                        self.chattingView.scrollToBottom(animated: true, force: true)
                    }
                })
            })
            self.chattingView.messages[self.chattingView.messages.index(of: resendableFileMessage)!] = preSendMessage
            self.chattingView.preSendMessages[preSendMessage.requestId!] = preSendMessage
            self.chattingView.preSendFileData[preSendMessage.requestId!] = self.chattingView.resendableFileData[resendableFileMessage.requestId!]
            self.chattingView.preSendFileData.removeValue(forKey: resendableFileMessage.requestId!)
            self.chattingView.chattingTableView.reloadData()
            DispatchQueue.main.async {
                self.chattingView.scrollToBottom(animated: true, force: true)
            }
        }
    }
    
    func clickDelete(view: UIView, message: SBDBaseMessage) {
        self.chattingView.messages.remove(at: self.chattingView.messages.index(of: message)!)
        DispatchQueue.main.async {
            self.chattingView.chattingTableView.reloadData()
        }
    }
    
    // MARK: UIImagePickerControllerDelegate
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        let mediaType = info[UIImagePickerControllerMediaType] as! String
        
        picker.dismiss(animated: true) {
            if CFStringCompare(mediaType as CFString, kUTTypeImage, []) == CFComparisonResult.compareEqualTo {
                let imagePath: URL = info[UIImagePickerControllerReferenceURL] as! URL
                
                let imageName: NSString = (imagePath.lastPathComponent as NSString?)!
                let ext = imageName.pathExtension
                let UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue()
                let mimeType = (UTTypeCopyPreferredTagWithClass(UTI!, kUTTagClassMIMEType)?.takeRetainedValue())! as String
                
                let asset = PHAsset.fetchAssets(withALAssetURLs: [imagePath], options: nil).lastObject
                let options = PHImageRequestOptions()
                options.isSynchronous = true
                options.isNetworkAccessAllowed = false
                options.deliveryMode = PHImageRequestOptionsDeliveryMode.highQualityFormat
                PHImageManager.default().requestImageData(for: asset!, options: options, resultHandler: { (imageData, dataUTI, orientation, info) in
                    let isError = info?[PHImageErrorKey]
                    let isCloud = info?[PHImageResultIsInCloudKey]
                    if ((isError != nil && (isError as! Bool) == true)) || (isCloud != nil && (isCloud as! Bool) == true) || imageData == nil {
                        // Fail.
                    }
                    else {
                        // sucess, data is in imagedata
                        /***********************************/
                        /* Thumbnail is a premium feature. */
                        /***********************************/
                        let thumbnailSize = SBDThumbnailSize.make(withMaxWidth: 320.0, maxHeight: 320.0)
                        
                        let preSendMessage = self.openChannel.sendFileMessage(withBinaryData: imageData!, filename: imageName as String, type: mimeType, size: UInt((imageData?.count)!), thumbnailSizes: [thumbnailSize!], data: "", customType: "", progressHandler: nil, completionHandler: { (fileMessage, error) in
                            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(150), execute: {
                                let preSendMessage = self.chattingView.preSendMessages[(fileMessage?.requestId)!] as! SBDFileMessage
                                self.chattingView.preSendMessages.removeValue(forKey: (fileMessage?.requestId)!)
                                
                                if error != nil {
                                    self.chattingView.resendableMessages[(fileMessage?.requestId)!] = preSendMessage
                                    self.chattingView.resendableFileData[preSendMessage.requestId!]?["data"] = imageData as AnyObject?
                                    self.chattingView.resendableFileData[preSendMessage.requestId!]?["type"] = mimeType as AnyObject?
                                    self.chattingView.chattingTableView.reloadData()
                                    DispatchQueue.main.async {
                                        self.chattingView.scrollToBottom(animated: true, force: true)
                                    }
                                    
                                    let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                                    let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                                    alert.addAction(closeAction)
                                    DispatchQueue.main.async {
                                        self.present(alert, animated: true, completion: nil)
                                    }
                                    
                                    return
                                }
                                if fileMessage != nil {
                                    self.chattingView.resendableMessages.removeValue(forKey: (fileMessage?.requestId)!)
                                    self.chattingView.resendableFileData.removeValue(forKey: (fileMessage?.requestId)!)
                                    self.chattingView.messages[self.chattingView.messages.index(of: preSendMessage)!] = fileMessage!
                                    
                                    DispatchQueue.main.async {
                                        self.chattingView.chattingTableView.reloadData()
                                        DispatchQueue.main.async {
                                            self.chattingView.scrollToBottom(animated: true, force: true)
                                        }
                                    }
                                }
                            })
                        })
                        
                        self.chattingView.preSendFileData[preSendMessage.requestId!] = [
                            "data": imageData as AnyObject,
                            "type": mimeType as AnyObject,
                        ]
                        self.chattingView.preSendMessages[preSendMessage.requestId!] = preSendMessage
                        self.chattingView.messages.append(preSendMessage)
                        self.chattingView.chattingTableView.reloadData()
                        DispatchQueue.main.async {
                            self.chattingView.scrollToBottom(animated: true, force: true)
                        }
                    }
                })
            }
            else if CFStringCompare(mediaType as CFString, kUTTypeMovie, []) == CFComparisonResult.compareEqualTo {
                let videoUrl: URL = info[UIImagePickerControllerMediaURL] as! URL
                let videoFileData = NSData(contentsOf: videoUrl)
                
                let videoName: NSString = (videoUrl.lastPathComponent as NSString?)!
                let ext = videoName.pathExtension
                let UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as NSString, nil)
                let mimeType = UTTypeCopyPreferredTagWithClass(UTI as! CFString, kUTTagClassMIMEType)?.takeRetainedValue()
                
                let preSendMessage = self.openChannel.sendFileMessage(withBinaryData: videoFileData! as Data, filename: videoName as String, type: mimeType! as String, size: UInt((videoFileData?.length)!), data: "", completionHandler: { (fileMessage, error) in
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(150), execute: {
                        DispatchQueue.main.async {
                            let preSendMessage = self.chattingView.preSendMessages[(fileMessage?.requestId!)!] as! SBDFileMessage
                            self.chattingView.preSendMessages.removeValue(forKey: (fileMessage?.requestId!)!)
                            
                            if error != nil {
                                self.chattingView.resendableMessages[(fileMessage?.requestId)!] = preSendMessage
                                self.chattingView.resendableFileData[preSendMessage.requestId!]?["data"] = videoFileData
                                self.chattingView.resendableFileData[preSendMessage.requestId!]?["type"] = mimeType
                                self.chattingView.chattingTableView.reloadData()
                                DispatchQueue.main.async {
                                    self.chattingView.scrollToBottom(animated: true, force: true)
                                }
                                
                                let alert = UIAlertController(title: Bundle.sbLocalizedStringForKey(key: "ErrorTitle"), message: error?.domain, preferredStyle: UIAlertControllerStyle.alert)
                                let closeAction = UIAlertAction(title: Bundle.sbLocalizedStringForKey(key: "CloseButton"), style: UIAlertActionStyle.cancel, handler: nil)
                                alert.addAction(closeAction)
                                DispatchQueue.main.async {
                                    self.present(alert, animated: true, completion: nil)
                                }
                                
                                return
                            }
                            
                            if fileMessage != nil {
                                self.chattingView.resendableMessages.removeValue(forKey: (fileMessage?.requestId!)!)
                                self.chattingView.resendableFileData.removeValue(forKey: (fileMessage?.requestId)!)
                                self.chattingView.messages[self.chattingView.messages.index(of: preSendMessage)!] = fileMessage!
                                
                                DispatchQueue.main.async {
                                    self.chattingView.chattingTableView.reloadData()
                                    DispatchQueue.main.async {
                                        self.chattingView.scrollToBottom(animated: true, force : false)
                                    }
                                }
                            }
                        }
                    })
                })
                
                self.chattingView.preSendFileData[preSendMessage.requestId!] = [
                    "data": videoFileData as AnyObject,
                    "type": mimeType as AnyObject,
                ]
                
                self.chattingView.preSendMessages[preSendMessage.requestId!] = preSendMessage
                self.chattingView.messages.append(preSendMessage)
                self.chattingView.chattingTableView.reloadData()
                DispatchQueue.main.async {
                    self.chattingView.scrollToBottom(animated: true, force: true)
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
