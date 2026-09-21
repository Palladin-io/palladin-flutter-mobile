import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @sharingAccountPending.
  ///
  /// In en, this message translates to:
  /// **'A shared entry is waiting. Finish signing in or setting up your account to return to it.'**
  String get sharingAccountPending;

  /// No description provided for @sharingCancelReception.
  ///
  /// In en, this message translates to:
  /// **'Cancel reception'**
  String get sharingCancelReception;

  /// No description provided for @sharingCancelAccountNotice.
  ///
  /// In en, this message translates to:
  /// **'Discard this reception from memory? You may need a new link to receive it again. This does not revoke the sender’s link or cancel your account setup.'**
  String get sharingCancelAccountNotice;

  /// No description provided for @sharingKeepReception.
  ///
  /// In en, this message translates to:
  /// **'Keep reception'**
  String get sharingKeepReception;

  /// No description provided for @sharingDiscardReception.
  ///
  /// In en, this message translates to:
  /// **'Discard reception'**
  String get sharingDiscardReception;

  /// No description provided for @sharingAccountNotice.
  ///
  /// In en, this message translates to:
  /// **'Receiving does not require an account. To save a copy, continue through your account and return here. This temporary session expires at its original deadline; closing it or signing out discards the copy.'**
  String get sharingAccountNotice;

  /// No description provided for @sharingRegister.
  ///
  /// In en, this message translates to:
  /// **'Create an account to save a copy'**
  String get sharingRegister;

  /// No description provided for @sharingLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in to save a copy'**
  String get sharingLogin;

  /// No description provided for @sharingContinueAccount.
  ///
  /// In en, this message translates to:
  /// **'Continue account setup or unlock'**
  String get sharingContinueAccount;

  /// No description provided for @sharingSaveCopy.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get sharingSaveCopy;

  /// No description provided for @sharingCopyCorruptVaults.
  ///
  /// In en, this message translates to:
  /// **'Some vaults could not be decrypted and are not offered as destinations. Other vaults remain available.'**
  String get sharingCopyCorruptVaults;

  /// No description provided for @sharingCopySaved.
  ///
  /// In en, this message translates to:
  /// **'Copy saved in your vault. It will not sync with the original.'**
  String get sharingCopySaved;

  /// No description provided for @sharingCopyNotice.
  ///
  /// In en, this message translates to:
  /// **'Save the received fields as a new entry. This does not receive the link again or change the original.'**
  String get sharingCopyNotice;

  /// No description provided for @sharingCopyVault.
  ///
  /// In en, this message translates to:
  /// **'Destination vault'**
  String get sharingCopyVault;

  /// No description provided for @sharingCopyChooseVault.
  ///
  /// In en, this message translates to:
  /// **'Choose a vault'**
  String get sharingCopyChooseVault;

  /// No description provided for @sharingCopyVaultError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your vaults. Try again while this sharing session is open.'**
  String get sharingCopyVaultError;

  /// No description provided for @sharingCopyNoVault.
  ///
  /// In en, this message translates to:
  /// **'There is no available destination vault for this account.'**
  String get sharingCopyNoVault;

  /// No description provided for @sharingCopyAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Access in the destination vault'**
  String get sharingCopyAccessTitle;

  /// No description provided for @sharingCopyAccessNotice.
  ///
  /// In en, this message translates to:
  /// **'Existing members and fully trusted Agents of this vault can access the copy. Source permissions are not copied; Discovery and individual field access for Agents start disabled.'**
  String get sharingCopyAccessNotice;

  /// No description provided for @sharingCopyTitleError.
  ///
  /// In en, this message translates to:
  /// **'Enter a name of 1–200 characters. The received name is never shortened automatically.'**
  String get sharingCopyTitleError;

  /// No description provided for @sharingCopyMissingNotice.
  ///
  /// In en, this message translates to:
  /// **'The sender left out fields required for a saved entry. Complete them here; received values stay unchanged.'**
  String get sharingCopyMissingNotice;

  /// No description provided for @sharingCopyRequired.
  ///
  /// In en, this message translates to:
  /// **'Complete this required field.'**
  String get sharingCopyRequired;

  /// No description provided for @sharingCopyScriptDescription.
  ///
  /// In en, this message translates to:
  /// **'Execution description for your copy'**
  String get sharingCopyScriptDescription;

  /// No description provided for @sharingCopyScriptError.
  ///
  /// In en, this message translates to:
  /// **'Provide a script, a supported interpreter (bash, sh, node or python), and an execution description of up to 4096 characters.'**
  String get sharingCopyScriptError;

  /// No description provided for @sharingCopyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This copy contains data this version cannot save without changing it. Nothing was saved.'**
  String get sharingCopyUnsupported;

  /// No description provided for @sharingCopySaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the copy for saving. Check your connection and destination access, then try again.'**
  String get sharingCopySaveError;

  /// No description provided for @sharingCopyRetryNotice.
  ///
  /// In en, this message translates to:
  /// **'The save result is not yet confirmed. Retry sends the same encrypted entry, not a duplicate. Do not start another save for this copy.'**
  String get sharingCopyRetryNotice;

  /// No description provided for @sharingCopyBack.
  ///
  /// In en, this message translates to:
  /// **'Back to received entry'**
  String get sharingCopyBack;

  /// No description provided for @sharingCopySessionNotice.
  ///
  /// In en, this message translates to:
  /// **'Leaving this sharing session, locking the app or switching apps discards this in-memory copy. It cannot undo a save already accepted by the server.'**
  String get sharingCopySessionNotice;

  /// No description provided for @sharingEndConfirm.
  ///
  /// In en, this message translates to:
  /// **'End link'**
  String get sharingEndConfirm;

  /// No description provided for @sharingReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared entry'**
  String get sharingReceiveTitle;

  /// No description provided for @sharingClose.
  ///
  /// In en, this message translates to:
  /// **'Close sharing'**
  String get sharingClose;

  /// No description provided for @sharingReceiveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This sharing link is unavailable. Reopen the original link if it is still valid.'**
  String get sharingReceiveUnavailable;

  /// No description provided for @sharingReceiveWelcome.
  ///
  /// In en, this message translates to:
  /// **'View a shared copy without creating an account. Opening the verification step does not use a receipt. You choose when to receive the entry.'**
  String get sharingReceiveWelcome;

  /// No description provided for @sharingOpen.
  ///
  /// In en, this message translates to:
  /// **'Open sharing'**
  String get sharingOpen;

  /// No description provided for @sharingReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive entry'**
  String get sharingReceive;

  /// No description provided for @sharingReceiveError.
  ///
  /// In en, this message translates to:
  /// **'This action could not be completed. Check the code or password if required, then try again. The link may have expired or been ended.'**
  String get sharingReceiveError;

  /// No description provided for @sharingOtpNotice.
  ///
  /// In en, this message translates to:
  /// **'Request a code at the email address chosen by the sender. No Palladin account is required.'**
  String get sharingOtpNotice;

  /// No description provided for @sharingSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send email code'**
  String get sharingSendOtp;

  /// No description provided for @sharingResendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get sharingResendOtp;

  /// No description provided for @sharingRetryOtp.
  ///
  /// In en, this message translates to:
  /// **'Retry code delivery'**
  String get sharingRetryOtp;

  /// No description provided for @sharingOtpCode.
  ///
  /// In en, this message translates to:
  /// **'Email code'**
  String get sharingOtpCode;

  /// No description provided for @sharingOtpFormatError.
  ///
  /// In en, this message translates to:
  /// **'Enter the six-digit email code.'**
  String get sharingOtpFormatError;

  /// No description provided for @sharingVerifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify email code'**
  String get sharingVerifyOtp;

  /// No description provided for @sharingVerifySecret.
  ///
  /// In en, this message translates to:
  /// **'Verify protection'**
  String get sharingVerifySecret;

  /// No description provided for @sharingReadyToReceive.
  ///
  /// In en, this message translates to:
  /// **'Verification is complete. Receiving the entry uses one receipt; retrying the same delivery does not use another.'**
  String get sharingReadyToReceive;

  /// No description provided for @sharingReceivedNotice.
  ///
  /// In en, this message translates to:
  /// **'This is a separate copy. Changes to the original do not update it. Ending the link cannot recall copies already received or change a password in another service.'**
  String get sharingReceivedNotice;

  /// No description provided for @sharingCopyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy value'**
  String get sharingCopyValue;

  /// No description provided for @sharingCopiedValue.
  ///
  /// In en, this message translates to:
  /// **'Copied. The clipboard clears after 45 seconds if its contents have not changed.'**
  String get sharingCopiedValue;

  /// No description provided for @sharingConfirmationFailed.
  ///
  /// In en, this message translates to:
  /// **'The entry is available, but display confirmation could not be sent. Retrying confirmation does not receive the entry again.'**
  String get sharingConfirmationFailed;

  /// No description provided for @sharingRetryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Retry confirmation'**
  String get sharingRetryConfirmation;

  /// No description provided for @sharingEnd.
  ///
  /// In en, this message translates to:
  /// **'End sharing'**
  String get sharingEnd;

  /// No description provided for @sharingEndNotice.
  ///
  /// In en, this message translates to:
  /// **'End this link for everyone who can use it? This cannot be undone. It does not delete the original entry or any copies already saved.'**
  String get sharingEndNotice;

  /// No description provided for @sharingEnded.
  ///
  /// In en, this message translates to:
  /// **'Sharing ended. This link can no longer deliver the entry.'**
  String get sharingEnded;

  /// No description provided for @sharingUnsupportedGate.
  ///
  /// In en, this message translates to:
  /// **'This link uses a verification method this app version does not support. Update the app or ask the sender for another link.'**
  String get sharingUnsupportedGate;

  /// No description provided for @sharingCreate.
  ///
  /// In en, this message translates to:
  /// **'Create sharing link'**
  String get sharingCreate;

  /// No description provided for @sharingSelectFields.
  ///
  /// In en, this message translates to:
  /// **'Choose fields to share'**
  String get sharingSelectFields;

  /// No description provided for @sharingSelectNotice.
  ///
  /// In en, this message translates to:
  /// **'Only selected fields will be copied. Notes, recovery codes and authenticator setup data require your explicit choice.'**
  String get sharingSelectNotice;

  /// No description provided for @sharingPreviewConfirmed.
  ///
  /// In en, this message translates to:
  /// **'I have checked the selected fields'**
  String get sharingPreviewConfirmed;

  /// No description provided for @sharingUnsupportedField.
  ///
  /// In en, this message translates to:
  /// **'This field cannot be shared by this version of the app.'**
  String get sharingUnsupportedField;

  /// No description provided for @sharingRecipient.
  ///
  /// In en, this message translates to:
  /// **'Who can receive this copy?'**
  String get sharingRecipient;

  /// No description provided for @sharingNamedRecipient.
  ///
  /// In en, this message translates to:
  /// **'Only this person (email code)'**
  String get sharingNamedRecipient;

  /// No description provided for @sharingEmail.
  ///
  /// In en, this message translates to:
  /// **'Recipient email'**
  String get sharingEmail;

  /// No description provided for @sharingEmailNotice.
  ///
  /// In en, this message translates to:
  /// **'Send the copied link yourself. Palladin emails only the verification code, not the link. Create a separate link for each person.'**
  String get sharingEmailNotice;

  /// No description provided for @sharingAnyoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link'**
  String get sharingAnyoneTitle;

  /// No description provided for @sharingAnyoneWarning.
  ///
  /// In en, this message translates to:
  /// **'The link can be forwarded. Its receipt limit is shared by everyone who has it; any authorized recipient can end it for everyone.'**
  String get sharingAnyoneWarning;

  /// No description provided for @sharingSecretNotice.
  ///
  /// In en, this message translates to:
  /// **'Send the password or PIN through a separate channel. It can be combined with the email code.'**
  String get sharingSecretNotice;

  /// No description provided for @sharingPinWarning.
  ///
  /// In en, this message translates to:
  /// **'A PIN is weaker than a long password. Use at least 6 digits; a password is recommended for stronger protection.'**
  String get sharingPinWarning;

  /// No description provided for @sharingLifetime.
  ///
  /// In en, this message translates to:
  /// **'Link lifetime'**
  String get sharingLifetime;

  /// No description provided for @sharingLifetimeHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get sharingLifetimeHour;

  /// No description provided for @sharingLifetimeDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get sharingLifetimeDay;

  /// No description provided for @sharingLifetimeThreeDays.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get sharingLifetimeThreeDays;

  /// No description provided for @sharingLifetimeWeek.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get sharingLifetimeWeek;

  /// No description provided for @sharingMaximumReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipt limit'**
  String get sharingMaximumReceipts;

  /// No description provided for @sharingNotifyChoice.
  ///
  /// In en, this message translates to:
  /// **'Notify me of the first receipt'**
  String get sharingNotifyChoice;

  /// No description provided for @sharingNotifyNotice.
  ///
  /// In en, this message translates to:
  /// **'One Inbox notification after the recipient confirms display. Audit events are always recorded; this is not proof a person read it.'**
  String get sharingNotifyNotice;

  /// No description provided for @sharingCreateNotice.
  ///
  /// In en, this message translates to:
  /// **'This is an independent copy, not access to your vault. It will not follow later edits. Revoking the link cannot recall downloaded copies.'**
  String get sharingCreateNotice;

  /// No description provided for @sharingCancelNotice.
  ///
  /// In en, this message translates to:
  /// **'If you leave after sending a request, check your sharing list: the link may already exist even if its response was lost.'**
  String get sharingCancelNotice;

  /// No description provided for @sharingEmailError.
  ///
  /// In en, this message translates to:
  /// **'Enter one valid recipient email address.'**
  String get sharingEmailError;

  /// No description provided for @sharingPasswordError.
  ///
  /// In en, this message translates to:
  /// **'Use 8–128 characters. Spaces count as part of the password.'**
  String get sharingPasswordError;

  /// No description provided for @sharingPinError.
  ///
  /// In en, this message translates to:
  /// **'Use 6–128 digits (0–9), without spaces.'**
  String get sharingPinError;

  /// No description provided for @sharingLimitError.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 1 to 100.'**
  String get sharingLimitError;

  /// No description provided for @sharingLifetimeError.
  ///
  /// In en, this message translates to:
  /// **'Choose one of the available lifetimes.'**
  String get sharingLifetimeError;

  /// No description provided for @sharingSelectionError.
  ///
  /// In en, this message translates to:
  /// **'Select at least one available field and check the preview.'**
  String get sharingSelectionError;

  /// No description provided for @sharingCreateError.
  ///
  /// In en, this message translates to:
  /// **'Could not create the link. Check your connection and try again.'**
  String get sharingCreateError;

  /// No description provided for @sharingSourceError.
  ///
  /// In en, this message translates to:
  /// **'The entry changed. Reopen it and check the fields before sharing again.'**
  String get sharingSourceError;

  /// No description provided for @sharingSourceLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not open this entry for sharing. Try again while unlocked.'**
  String get sharingSourceLoadError;

  /// No description provided for @sharingRetryNotice.
  ///
  /// In en, this message translates to:
  /// **'The result is uncertain. Retry sends the exact same encrypted copy and does not create a second link. Options are locked until this is resolved.'**
  String get sharingRetryNotice;

  /// No description provided for @sharingRetryCreate.
  ///
  /// In en, this message translates to:
  /// **'Retry same request'**
  String get sharingRetryCreate;

  /// No description provided for @sharingCreated.
  ///
  /// In en, this message translates to:
  /// **'Your sharing link is ready'**
  String get sharingCreated;

  /// No description provided for @sharingCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy sharing link'**
  String get sharingCopyLink;

  /// No description provided for @sharingCopiedLink.
  ///
  /// In en, this message translates to:
  /// **'Sharing link copied. Clipboard clears after 45 seconds if unchanged.'**
  String get sharingCopiedLink;

  /// No description provided for @sharingCopyError.
  ///
  /// In en, this message translates to:
  /// **'Could not copy the link. Try again while this screen is open.'**
  String get sharingCopyError;

  /// No description provided for @sharingLinkOnceNotice.
  ///
  /// In en, this message translates to:
  /// **'Copy this link before leaving. Palladin cannot recover its decryption key later. You can still revoke it from the sharing list.'**
  String get sharingLinkOnceNotice;

  /// No description provided for @sharingConfigurationError.
  ///
  /// In en, this message translates to:
  /// **'Sharing is not configured for this app environment. No link has been created.'**
  String get sharingConfigurationError;

  /// No description provided for @sharingTotpSource.
  ///
  /// In en, this message translates to:
  /// **'Authenticator setup data'**
  String get sharingTotpSource;

  /// No description provided for @sharingHidePreview.
  ///
  /// In en, this message translates to:
  /// **'Hide value'**
  String get sharingHidePreview;

  /// No description provided for @sharingTab.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get sharingTab;

  /// No description provided for @sharingListNotice.
  ///
  /// In en, this message translates to:
  /// **'Links contain independent copies. Delivery and display confirmation are separate; neither proves a person read the entry.'**
  String get sharingListNotice;

  /// No description provided for @sharingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sharing links for this entry.'**
  String get sharingEmpty;

  /// No description provided for @sharingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sharing is unavailable in this session. Reopen the entry after unlocking.'**
  String get sharingUnavailable;

  /// No description provided for @sharingLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load sharing links.'**
  String get sharingLoadError;

  /// No description provided for @sharingRevokeError.
  ///
  /// In en, this message translates to:
  /// **'Could not revoke the link. Check its status and try again.'**
  String get sharingRevokeError;

  /// No description provided for @sharingRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke link'**
  String get sharingRevoke;

  /// No description provided for @sharingRevokeNotice.
  ///
  /// In en, this message translates to:
  /// **'This stops future access through the link. It cannot remove downloaded copies or change the password in another service.'**
  String get sharingRevokeNotice;

  /// No description provided for @sharingRevoked.
  ///
  /// In en, this message translates to:
  /// **'Sharing link revoked.'**
  String get sharingRevoked;

  /// No description provided for @sharingRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sharingRefresh;

  /// No description provided for @sharingAnyone.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link'**
  String get sharingAnyone;

  /// No description provided for @sharingActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get sharingActive;

  /// No description provided for @sharingRevokedStatus.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get sharingRevokedStatus;

  /// No description provided for @sharingExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get sharingExpired;

  /// No description provided for @sharingSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get sharingSuspended;

  /// No description provided for @sharingLocked.
  ///
  /// In en, this message translates to:
  /// **'Temporarily locked'**
  String get sharingLocked;

  /// No description provided for @sharingConsumed.
  ///
  /// In en, this message translates to:
  /// **'Receipt limit reached'**
  String get sharingConsumed;

  /// No description provided for @sharingProtectionNone.
  ///
  /// In en, this message translates to:
  /// **'No additional secret'**
  String get sharingProtectionNone;

  /// No description provided for @sharingProtectionPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sharingProtectionPassword;

  /// No description provided for @sharingProtectionPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get sharingProtectionPin;

  /// No description provided for @sharingValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Link valid until'**
  String get sharingValidUntil;

  /// No description provided for @sharingReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts / limit'**
  String get sharingReceipts;

  /// No description provided for @sharingFirstDelivery.
  ///
  /// In en, this message translates to:
  /// **'First delivery'**
  String get sharingFirstDelivery;

  /// No description provided for @sharingLastDelivery.
  ///
  /// In en, this message translates to:
  /// **'Last delivery'**
  String get sharingLastDelivery;

  /// No description provided for @sharingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'First display confirmation'**
  String get sharingConfirmation;

  /// No description provided for @sharingProtection.
  ///
  /// In en, this message translates to:
  /// **'Additional protection'**
  String get sharingProtection;

  /// No description provided for @sharingNotification.
  ///
  /// In en, this message translates to:
  /// **'First-receipt notification'**
  String get sharingNotification;

  /// No description provided for @sharingNotificationOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled — one Inbox notification'**
  String get sharingNotificationOn;

  /// No description provided for @sharingNotificationOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get sharingNotificationOff;

  /// No description provided for @sharingSourceChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Source changed'**
  String get sharingSourceChangedTitle;

  /// No description provided for @sharingSourceChanged.
  ///
  /// In en, this message translates to:
  /// **'This copy does not update when the original entry changes. Revoke it if it should no longer be available.'**
  String get sharingSourceChanged;

  /// No description provided for @responseUnknownValue.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get responseUnknownValue;

  /// The application title shown in the app bar and OS task switcher
  ///
  /// In en, this message translates to:
  /// **'Palladin'**
  String get appTitle;

  /// Greeting shown on the home/dashboard placeholder page
  ///
  /// In en, this message translates to:
  /// **'Welcome to Palladin'**
  String get welcomeMessage;

  /// Rotating welcome line on the login screen — zero-knowledge
  ///
  /// In en, this message translates to:
  /// **'Zero-knowledge by design.'**
  String get loginRotatingZeroKnowledge;

  /// Rotating welcome line on the login screen — built for agents
  ///
  /// In en, this message translates to:
  /// **'Built for AI agents.'**
  String get loginRotatingForAgents;

  /// Rotating welcome line on the login screen — your keys
  ///
  /// In en, this message translates to:
  /// **'Your keys, your rules.'**
  String get loginRotatingYourKeys;

  /// Rotating welcome line on the login screen — always encrypted
  ///
  /// In en, this message translates to:
  /// **'Always encrypted.'**
  String get loginRotatingEncrypted;

  /// Label for the Google OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// Label for the Apple OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// Label for the X (formerly Twitter) OAuth sign-in button
  ///
  /// In en, this message translates to:
  /// **'Sign in with X'**
  String get continueWithX;

  /// Button that opens the email and master password sign-in form
  ///
  /// In en, this message translates to:
  /// **'Continue with Email'**
  String get continueWithEmail;

  /// Button that returns from the email form to the sign-in method picker
  ///
  /// In en, this message translates to:
  /// **'Other sign-in options'**
  String get authOtherSignInOptions;

  /// No description provided for @legalFooterPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our '**
  String get legalFooterPrefix;

  /// No description provided for @legalTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get legalTermsLink;

  /// No description provided for @legalFooterSeparator.
  ///
  /// In en, this message translates to:
  /// **' & '**
  String get legalFooterSeparator;

  /// No description provided for @legalPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get legalPrivacyLink;

  /// No description provided for @legalLinkOpenError.
  ///
  /// In en, this message translates to:
  /// **'Unable to open this link.'**
  String get legalLinkOpenError;

  /// Snackbar message when a disabled OAuth provider is tapped
  ///
  /// In en, this message translates to:
  /// **'{provider} sign-in coming soon'**
  String providerComingSoon(String provider);

  /// Error shown when the backend request times out
  ///
  /// In en, this message translates to:
  /// **'Server not responding. Please try again.'**
  String get errorServerNotResponding;

  /// Error shown when a network/socket connection fails
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to server. Check your connection and try again.'**
  String get errorCannotConnectToServer;

  /// Generic fallback error for other Dio/connection failures
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please try again.'**
  String get errorConnectionFailed;

  /// Error shown when the backend returns unparseable data
  ///
  /// In en, this message translates to:
  /// **'Invalid server response. Please try again.'**
  String get errorInvalidServerResponse;

  /// Headline on the master password setup screen
  ///
  /// In en, this message translates to:
  /// **'Set Your Master Password'**
  String get onboardingMasterPasswordTitle;

  /// Supporting copy below the master password headline
  ///
  /// In en, this message translates to:
  /// **'This password encrypts your vault locally. We never see it.'**
  String get onboardingMasterPasswordSubtitle;

  /// Label for the master password input field
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get onboardingMasterPasswordLabel;

  /// Label for the password confirmation input field
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get onboardingConfirmPasswordLabel;

  /// Title for the password requirements checklist
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get onboardingPasswordRequirementsTitle;

  /// Requirement: password length
  ///
  /// In en, this message translates to:
  /// **'At least 12 characters'**
  String get onboardingPasswordReqLength;

  /// Requirement: mixed case
  ///
  /// In en, this message translates to:
  /// **'Uppercase & lowercase'**
  String get onboardingPasswordReqCase;

  /// Requirement: digit
  ///
  /// In en, this message translates to:
  /// **'At least one number'**
  String get onboardingPasswordReqNumber;

  /// Requirement: symbol
  ///
  /// In en, this message translates to:
  /// **'At least one symbol'**
  String get onboardingPasswordReqSymbol;

  /// Strength label when the password is under 8 characters
  ///
  /// In en, this message translates to:
  /// **'Too short'**
  String get onboardingPasswordStrengthTooShort;

  /// Strength label for a weak password
  ///
  /// In en, this message translates to:
  /// **'Weak password'**
  String get onboardingPasswordStrengthWeak;

  /// Strength label for a fair password
  ///
  /// In en, this message translates to:
  /// **'Fair password'**
  String get onboardingPasswordStrengthFair;

  /// Strength label for a strong password
  ///
  /// In en, this message translates to:
  /// **'Strong password'**
  String get onboardingPasswordStrengthStrong;

  /// Strength label for a very strong password
  ///
  /// In en, this message translates to:
  /// **'Very strong password'**
  String get onboardingPasswordStrengthVeryStrong;

  /// Inline confirmation when both password fields match
  ///
  /// In en, this message translates to:
  /// **'Passwords match'**
  String get onboardingPasswordsMatch;

  /// Inline error when the two password fields disagree
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get onboardingPasswordsDoNotMatch;

  /// Primary button on screen 1
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// Headline on the recovery key backup screen
  ///
  /// In en, this message translates to:
  /// **'Save Your Recovery Key'**
  String get onboardingRecoveryTitle;

  /// Supporting copy on the recovery key backup screen
  ///
  /// In en, this message translates to:
  /// **'Write this down and store it safely offline. Without it, a forgotten master password means permanent data loss.'**
  String get onboardingRecoverySubtitle;

  /// Warning banner reminding the user to store the recovery key safely
  ///
  /// In en, this message translates to:
  /// **'You cannot recover your vault without this key.'**
  String get onboardingRecoveryWarning;

  /// Button that copies the recovery mnemonic to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get onboardingRecoveryCopy;

  /// Snackbar confirmation after copying the recovery mnemonic
  ///
  /// In en, this message translates to:
  /// **'Recovery key copied to clipboard'**
  String get onboardingRecoveryCopied;

  /// Button that exports the recovery mnemonic as a .txt file via the platform share sheet
  ///
  /// In en, this message translates to:
  /// **'Export as File (.txt)'**
  String get onboardingRecoveryExport;

  /// Primary button on screen 2 to proceed to confirmation
  ///
  /// In en, this message translates to:
  /// **'I\'ve Saved My Recovery Key'**
  String get onboardingRecoverySaved;

  /// Headline on the recovery key confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Confirm Recovery Key'**
  String get onboardingConfirmTitle;

  /// Supporting copy on the recovery key confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Enter the following words from your recovery key to verify you saved it.'**
  String get onboardingConfirmSubtitle;

  /// Label for a single recovery-word input on the confirmation screen
  ///
  /// In en, this message translates to:
  /// **'Word #{index}'**
  String onboardingConfirmWordLabel(int index);

  /// Placeholder text for a recovery-word input
  ///
  /// In en, this message translates to:
  /// **'Enter word #{index}'**
  String onboardingConfirmWordHint(int index);

  /// Inline confirmation shown when a recovery word matches
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get onboardingConfirmCorrect;

  /// Inline error shown when a recovery word does not match
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get onboardingConfirmIncorrect;

  /// Primary button on screen 3 that runs the crypto pipeline
  ///
  /// In en, this message translates to:
  /// **'Verify & Complete Setup'**
  String get onboardingConfirmVerify;

  /// Error shown when the backend returns 409 during setup
  ///
  /// In en, this message translates to:
  /// **'This account has already been set up. Please sign in again.'**
  String get onboardingAlreadyCompleted;

  /// Subtitle on the master-password unlock screen
  ///
  /// In en, this message translates to:
  /// **'Enter your master password'**
  String get unlockTitle;

  /// Label for the password field on the unlock screen
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get unlockPasswordLabel;

  /// Primary action label on the unlock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// Text button that starts the recovery-key flow
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get unlockForgotPassword;

  /// Snackbar shown until the recovery-key flow is implemented
  ///
  /// In en, this message translates to:
  /// **'Recovery flow coming soon'**
  String get unlockForgotPasswordComingSoon;

  /// Error shown when password-based decryption fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect master password. Please try again.'**
  String get unlockWrongPassword;

  /// Error shown when the session/refresh token has expired and the account material can't be fetched — the user is routed back to sign-in
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get unlockSessionExpired;

  /// Tooltip and caption for the biometric unlock button
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockBiometricHint;

  /// Localized reason passed to the OS biometric prompt
  ///
  /// In en, this message translates to:
  /// **'Authenticate to unlock your vault'**
  String get unlockBiometricPrompt;

  /// Android BiometricPrompt title for the biometric unlock/enroll dialog
  ///
  /// In en, this message translates to:
  /// **'Unlock Palladin'**
  String get unlockBiometricPromptTitle;

  /// Reason shown when enrolling the master key into biometric-gated storage
  ///
  /// In en, this message translates to:
  /// **'Confirm to enable biometric unlock'**
  String get unlockBiometricEnrollPrompt;

  /// Error when no MK has been stashed yet for biometric unlock
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not set up on this device. Enter your master password.'**
  String get unlockBiometricUnavailable;

  /// Error when the OS biometric prompt is cancelled or fails
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication failed. Please try again or use your password.'**
  String get unlockBiometricFailed;

  /// Tooltip on the lock-vault action in the home app bar
  ///
  /// In en, this message translates to:
  /// **'Lock Vault'**
  String get unlockLockVault;

  /// Headline on the first recovery step where the user enters their 24-word key
  ///
  /// In en, this message translates to:
  /// **'Recover Your Account'**
  String get recoveryTitle;

  /// Supporting copy explaining what recovery does on the enter-key step
  ///
  /// In en, this message translates to:
  /// **'Enter your 24-word recovery key. We\'ll use it to unwrap your vault locally — nothing is sent to our servers unencrypted.'**
  String get recoverySubtitle;

  /// Hint text shown inside the mnemonic text area
  ///
  /// In en, this message translates to:
  /// **'Type or paste your 24 recovery words, separated by spaces'**
  String get recoveryEnterKeyLabel;

  /// Secondary button that pastes the mnemonic from the clipboard
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get recoveryPasteButton;

  /// Subject line used when sharing the recovery key file via the platform share sheet
  ///
  /// In en, this message translates to:
  /// **'Palladin Recovery Key'**
  String get recoveryShareSubject;

  /// Secondary button that imports the mnemonic from a file
  ///
  /// In en, this message translates to:
  /// **'Import from .txt File'**
  String get recoveryImportButton;

  /// Snackbar shown when the user taps import before the file picker is wired up
  ///
  /// In en, this message translates to:
  /// **'File import coming soon — paste from clipboard instead'**
  String get recoveryImportComingSoon;

  /// Headline on the second recovery step
  ///
  /// In en, this message translates to:
  /// **'Set a New Master Password'**
  String get recoveryNewPasswordTitle;

  /// Supporting copy on the new-password recovery step
  ///
  /// In en, this message translates to:
  /// **'Choose a new master password. It will replace the one you forgot.'**
  String get recoveryNewPasswordSubtitle;

  /// Label for the new password input
  ///
  /// In en, this message translates to:
  /// **'New Master Password'**
  String get recoveryNewPasswordLabel;

  /// Label for the password confirmation input
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get recoveryConfirmPasswordLabel;

  /// Primary button that triggers the full recovery pipeline
  ///
  /// In en, this message translates to:
  /// **'Recover Account'**
  String get recoveryRecoverButton;

  /// Headline on the final recovery step where the freshly generated mnemonic is displayed
  ///
  /// In en, this message translates to:
  /// **'Save Your New Recovery Key'**
  String get recoverySaveKeyTitle;

  /// Checkbox the user must tick before finishing recovery
  ///
  /// In en, this message translates to:
  /// **'I\'ve saved my new recovery key in a safe place'**
  String get recoverySaveKeyCheckbox;

  /// Primary button that closes the recovery flow
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get recoveryFinishButton;

  /// Button that copies the new recovery mnemonic to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get recoveryCopyButton;

  /// Error shown when the supplied mnemonic fails to decrypt the wrapped private key
  ///
  /// In en, this message translates to:
  /// **'This recovery key doesn\'t match our records. Double-check your 24 words and try again.'**
  String get recoveryWrongKey;

  /// Inline error when the new password and its confirmation disagree
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get recoveryPasswordMismatch;

  /// Error when the backend returns an account without recovery salt/ciphertext
  ///
  /// In en, this message translates to:
  /// **'This account cannot be recovered — no recovery key was set up. Please contact support.'**
  String get recoveryMaterialMissing;

  /// Generic fallback error for the recovery flow
  ///
  /// In en, this message translates to:
  /// **'Recovery failed. Please try again.'**
  String get recoveryServerError;

  /// Vaults section title shown in the app bar of the vault list
  ///
  /// In en, this message translates to:
  /// **'Vaults'**
  String get vaultTitle;

  /// Label of the button / FAB that opens the create-vault sheet
  ///
  /// In en, this message translates to:
  /// **'New Vault'**
  String get vaultNewVault;

  /// Empty-state title when the user has no vaults
  ///
  /// In en, this message translates to:
  /// **'No vaults yet'**
  String get vaultNoVaults;

  /// Empty-state subtitle shown alongside the create-vault CTA
  ///
  /// In en, this message translates to:
  /// **'Create your first vault to organize credentials and grant access to your AI agents.'**
  String get vaultCreateFirst;

  /// Retry button label on the vault list error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get vaultRetry;

  /// Generic cancel button label used in vault dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get vaultCancel;

  /// Label for the Full grant mode (one approval covers the whole vault)
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get vaultModeFull;

  /// Label for the Granular grant mode (per-entry approvals)
  ///
  /// In en, this message translates to:
  /// **'Granular'**
  String get vaultModeGranular;

  /// Subtitle for the Full mode option in the vault form
  ///
  /// In en, this message translates to:
  /// **'One approval grants access to every entry.'**
  String get vaultModeFullDescription;

  /// Subtitle for the Granular mode option in the vault form
  ///
  /// In en, this message translates to:
  /// **'Each entry needs its own approval.'**
  String get vaultModeGranularDescription;

  /// Label above the grant mode selector in the vault form
  ///
  /// In en, this message translates to:
  /// **'Grant mode'**
  String get vaultModeLabel;

  /// Label for the vault name field
  ///
  /// In en, this message translates to:
  /// **'Vault Name'**
  String get vaultNameLabel;

  /// Label for the optional vault description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get vaultDescriptionLabel;

  /// Label above the icon picker in the vault form
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get vaultIconLabel;

  /// Label above the color picker in the vault form
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vaultColorLabel;

  /// Loading label shown on the create button while the vault is being created
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get vaultCreating;

  /// Loading label shown on the save button while the vault is being updated
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get vaultSaving;

  /// Snackbar shown after a successful vault update
  ///
  /// In en, this message translates to:
  /// **'Vault updated'**
  String get vaultSavedSnackbar;

  /// Title of the delete-vault confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Vault?'**
  String get vaultDeleteTitle;

  /// Body of the delete-vault confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\" and all its entries. This cannot be undone.'**
  String vaultDeleteConfirmWithName(String name);

  /// Title of the vault settings page
  ///
  /// In en, this message translates to:
  /// **'Vault Settings'**
  String get vaultSettings;

  /// Save button label on the vault settings page
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get vaultSaveChanges;

  /// Section label for destructive actions on the vault settings page
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get vaultDangerZone;

  /// Explanatory text under the danger zone heading
  ///
  /// In en, this message translates to:
  /// **'Deleting a vault is permanent — entries and grants are removed too.'**
  String get vaultDangerZoneSubtitle;

  /// Destructive action button label
  ///
  /// In en, this message translates to:
  /// **'Delete Vault'**
  String get vaultDeleteVault;

  /// Vault card meta line: number of entries
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries} =1{1 entry} other{{count} entries}}'**
  String vaultEntryCount(int count);

  /// Vault card meta line: when the vault was last updated
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String vaultUpdatedAt(String date);

  /// Relative timestamp label shown on a vault card when the vault was updated less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get vaultUpdatedNow;

  /// Relative timestamp shown on a vault card when the last update was less than an hour ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1m ago} other{{count}m ago}}'**
  String vaultUpdatedMinutesAgo(int count);

  /// Relative timestamp shown on a vault card when the last update was less than a day ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1h ago} other{{count}h ago}}'**
  String vaultUpdatedHoursAgo(int count);

  /// Relative timestamp shown on a vault card when the last update was less than 30 days ago
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1d ago} other{{count}d ago}}'**
  String vaultUpdatedDaysAgo(int count);

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultStatEntries;

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Active grants'**
  String get vaultStatActiveGrants;

  /// Stat chip label on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get vaultStatMembers;

  /// Section heading on the vault detail page for the entries list
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultSectionEntries;

  /// Section heading on the vault detail page for the agents list
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get vaultSectionAgents;

  /// Placeholder card title under Entries on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Entries coming soon'**
  String get vaultEntriesPlaceholderTitle;

  /// Placeholder card body under Entries on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Add and manage credentials from the web panel for now — mobile entry management lands in the next phase.'**
  String get vaultEntriesPlaceholderSubtitle;

  /// Placeholder card title under Agents on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Agents coming soon'**
  String get vaultAgentsPlaceholderTitle;

  /// Placeholder card body under Agents on the vault detail page
  ///
  /// In en, this message translates to:
  /// **'Approve agent grants from the home screen — per-vault agent management is on the roadmap.'**
  String get vaultAgentsPlaceholderSubtitle;

  /// Error shown when the backend returns 404 for a vault operation
  ///
  /// In en, this message translates to:
  /// **'This vault no longer exists.'**
  String get vaultErrorNotFound;

  /// Error shown when the backend returns 403 without a more specific reason
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get vaultErrorForbidden;

  /// Error shown when the user has hit the vault count cap for their billing plan
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the vault limit for your plan. Upgrade to create more.'**
  String get vaultErrorPlanLimitReached;

  /// Error shown when the user tries to create a Full-mode vault on a plan that doesn't support it
  ///
  /// In en, this message translates to:
  /// **'Your plan doesn\'t allow Full-mode vaults. Choose Granular or upgrade.'**
  String get vaultErrorFullModeNotAllowed;

  /// Generic fallback error for vault operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get vaultErrorUnknown;

  /// Vault card header right-side label: count of grants on the vault
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No grants} =1{1 grant} other{{count} grants}}'**
  String vaultGrantCount(int count);

  /// Vault card footer label: number of currently active grants
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active grants} =1{1 active grant} other{{count} active grants}}'**
  String vaultActiveGrantCount(int count);

  /// Vault detail tab — Entries
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get vaultTabEntries;

  /// Vault detail tab — Agents
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get vaultTabAgents;

  /// Vault detail tab — Logs
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get vaultTabLogs;

  /// Vault detail tab — Members
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get vaultTabMembers;

  /// Vault detail tab — Settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get vaultTabSettings;

  /// Placeholder for the search input on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Search entries…'**
  String get vaultSearchEntries;

  /// Placeholder for the search input on the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Search agents…'**
  String get vaultSearchAgents;

  /// Mode label on a grant card — full vault access
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get vaultGrantFull;

  /// Mode label on a grant card — per-entry access
  ///
  /// In en, this message translates to:
  /// **'Granular'**
  String get vaultGrantGranular;

  /// Status pill on the grant card — currently active
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get vaultGrantActive;

  /// Status pill on the grant card — expired
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get vaultGrantExpired;

  /// Status pill on the grant card — revoked by the vault owner
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get vaultGrantRevoked;

  /// Footer line on an active / expired grant card
  ///
  /// In en, this message translates to:
  /// **'Granted by {person} at {date}'**
  String vaultGrantGrantedBy(String person, String date);

  /// Footer line on a revoked grant card
  ///
  /// In en, this message translates to:
  /// **'Revoked by {person} at {date}'**
  String vaultGrantRevokedBy(String person, String date);

  /// Trailing chip indicating extra entries hidden inside a granular grant
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String vaultGrantMoreEntries(int count);

  /// Action button on an active grant card
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get vaultRevokeButton;

  /// Action button on a revoked grant card
  ///
  /// In en, this message translates to:
  /// **'Re-grant'**
  String get vaultRegrantButton;

  /// Action button on an expired grant card
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get vaultRestoreButton;

  /// Empty-state title for the Entries tab when no entries exist
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get vaultEntriesEmpty;

  /// Empty-state title for the Agents tab when no grants exist
  ///
  /// In en, this message translates to:
  /// **'No agents granted access'**
  String get vaultAgentsEmpty;

  /// Entry Agents tab — empty state title
  ///
  /// In en, this message translates to:
  /// **'No agents have access'**
  String get entryAgentsEmptyTitle;

  /// Entry Agents tab — empty state hint
  ///
  /// In en, this message translates to:
  /// **'No agent has been granted access to this entry yet.'**
  String get entryAgentsEmptyHint;

  /// Vault Agents tab — empty state title
  ///
  /// In en, this message translates to:
  /// **'No agents have access'**
  String get vaultAgentsEmptyTitle;

  /// Vault Agents tab — empty hint
  ///
  /// In en, this message translates to:
  /// **'No agent has been granted access to this vault yet.'**
  String get vaultAgentsEmptyHint;

  /// Placeholder copy on the Logs tab
  ///
  /// In en, this message translates to:
  /// **'Activity log coming soon'**
  String get vaultLogsEmpty;

  /// Placeholder copy on the Members tab
  ///
  /// In en, this message translates to:
  /// **'Member management coming soon'**
  String get vaultMembersEmpty;

  /// Tooltip on the entry-row reveal button
  ///
  /// In en, this message translates to:
  /// **'Reveal entry data'**
  String get vaultRevealEntry;

  /// Tooltip on the entry-row arrow button
  ///
  /// In en, this message translates to:
  /// **'View entry details'**
  String get vaultViewEntry;

  /// Tooltip on the copy-to-clipboard button inside a revealed entry panel
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get vaultCopyValue;

  /// Tooltip on the open-in-browser button inside a revealed entry panel
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get vaultOpenLink;

  /// Tooltip on the visibility-toggle button next to a masked value
  ///
  /// In en, this message translates to:
  /// **'Reveal value'**
  String get vaultRevealValue;

  /// AppBar action label on the vault settings tab
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get vaultSaveAction;

  /// Tooltip / accessibility label for the FAB on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get vaultAddEntryFab;

  /// Tooltip / accessibility label for the FAB on the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Add grant'**
  String get vaultAddGrantFab;

  /// Tooltip for the upload-custom-icon button in the icon picker
  ///
  /// In en, this message translates to:
  /// **'Upload custom icon'**
  String get vaultIconUpload;

  /// Error shown when S3 icon upload fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Please try again.'**
  String get vaultIconUploadError;

  /// Error shown when selected file is too large
  ///
  /// In en, this message translates to:
  /// **'File exceeds 2 MB limit.'**
  String get vaultIconUploadSizeError;

  /// Error shown when selected file has an unsupported format
  ///
  /// In en, this message translates to:
  /// **'Unsupported format. Use PNG, JPEG or WebP.'**
  String get vaultIconUploadFormatError;

  /// Label for the Pro-upgrade FAB shown when a Basic-plan user has hit the single-vault limit
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get vaultUpgradeToPro;

  /// Snackbar shown when the user taps the upgrade FAB before the billing flow ships
  ///
  /// In en, this message translates to:
  /// **'Upgrade flow coming soon — you\'ve reached the Basic plan\'s single-vault limit.'**
  String get vaultUpgradeComingSoon;

  /// Bottom nav label for the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom nav label for the Vaults tab
  ///
  /// In en, this message translates to:
  /// **'Vaults'**
  String get navVaults;

  /// Bottom nav label for the Agents tab
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get navAgents;

  /// Bottom nav label for the Audit tab
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get navAudit;

  /// Bottom nav label for the Approvals (pending grants) tab
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get navApprovals;

  /// Bottom nav label for the business notification inbox
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navInbox;

  /// Bottom nav label for the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Header title shown on the vault list page
  ///
  /// In en, this message translates to:
  /// **'My Vaults'**
  String get vaultListTitle;

  /// Subtitle under the vault list header — count of vaults and total entries across them
  ///
  /// In en, this message translates to:
  /// **'{vaultCount, plural, =1{1 vault} other{{vaultCount} vaults}} · {entryCount, plural, =0{no entries} =1{1 entry} other{{entryCount} entries}}'**
  String vaultListSummary(int vaultCount, int entryCount);

  /// Placeholder for the search input on the vault list page
  ///
  /// In en, this message translates to:
  /// **'Search vaults…'**
  String get vaultSearchHint;

  /// Empty-state title when a search query has no matches in the vault list
  ///
  /// In en, this message translates to:
  /// **'No vaults match your search'**
  String get vaultSearchEmpty;

  /// Section title in the settings drawer for account-related actions
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountTitle;

  /// Settings drawer item: lock the vault but keep the user signed in
  ///
  /// In en, this message translates to:
  /// **'Lock Vault'**
  String get settingsLockVault;

  /// Settings drawer item: full sign-out, returns to the login screen
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogout;

  /// Footer text in the settings drawer showing the app version
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAppVersion(String version);

  /// Accessibility / tooltip label for the settings icon button in the vault list header
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingsTooltip;

  /// Headline of the premium-gate bottom sheet shown when a Basic-plan user taps the New Vault FAB
  ///
  /// In en, this message translates to:
  /// **'Unlock unlimited vaults'**
  String get premiumGateTitle;

  /// Supporting copy on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the 1-vault limit on the free plan.'**
  String get premiumGateSubtitle;

  /// Primary CTA on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get premiumGateCta;

  /// Secondary / dismiss button on the premium-gate bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get premiumGateDismiss;

  /// Settings drawer row label for the dark/light theme toggle
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsThemeToggle;

  /// Settings drawer row label for the EN/PL language selector
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Plan badge in the settings drawer header for users with the premium permission bit set
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get settingsPlanPro;

  /// Plan label in the settings drawer header for users on the free plan
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get settingsPlanFree;

  /// Fallback display name shown in the settings drawer header when the user's email is missing or empty
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get settingsDefaultDisplayName;

  /// Generic 'coming soon' label used on placeholder pages for tabs not yet implemented
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get placeholderComingSoon;

  /// Page title for the Audit placeholder page — distinct from the bottom-nav 'Audit' label so the page reads as a full screen heading
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get placeholderAuditTitle;

  /// AppBar title on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Add Entry'**
  String get entryAddTitle;

  /// AppBar title on the Entry Detail page when no label is known yet
  ///
  /// In en, this message translates to:
  /// **'Entry Details'**
  String get entryDetailTitle;

  /// Details tab label on the Entry Detail page (contains the edit form)
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get entryTabDetails;

  /// Shown while the detail page is decrypting the entry payload before the form can be shown
  ///
  /// In en, this message translates to:
  /// **'Loading entry data…'**
  String get entryRevealingForEdit;

  /// No description provided for @entryRevealDetailsAction.
  ///
  /// In en, this message translates to:
  /// **'Reveal entry details'**
  String get entryRevealDetailsAction;

  /// No description provided for @entryRevealDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Sensitive fields are decrypted only after you request them.'**
  String get entryRevealDetailsHint;

  /// No description provided for @entryErrorConflict.
  ///
  /// In en, this message translates to:
  /// **'This entry changed while you were editing it. Reload it and try again.'**
  String get entryErrorConflict;

  /// No description provided for @entryAgentsPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent visibility'**
  String get entryAgentsPolicyTitle;

  /// No description provided for @entryAgentsPolicyHint.
  ///
  /// In en, this message translates to:
  /// **'Choose what agents may discover and what can be released by an exact-revision grant.'**
  String get entryAgentsPolicyHint;

  /// No description provided for @entryAgentsDiscoverable.
  ///
  /// In en, this message translates to:
  /// **'Discoverable by organization agents'**
  String get entryAgentsDiscoverable;

  /// No description provided for @entryAgentsAgentLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent-facing label'**
  String get entryAgentsAgentLabel;

  /// No description provided for @entryAgentsDiscoveryPreview.
  ///
  /// In en, this message translates to:
  /// **'Discovery preview'**
  String get entryAgentsDiscoveryPreview;

  /// No description provided for @entryAgentsDiscoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No values will be included in Discovery.'**
  String get entryAgentsDiscoveryEmpty;

  /// No description provided for @entryAgentsSavePolicy.
  ///
  /// In en, this message translates to:
  /// **'Save visibility policy'**
  String get entryAgentsSavePolicy;

  /// No description provided for @entryAgentsSavingPolicy.
  ///
  /// In en, this message translates to:
  /// **'Saving policy…'**
  String get entryAgentsSavingPolicy;

  /// No description provided for @entryAgentsPolicyError.
  ///
  /// In en, this message translates to:
  /// **'The encrypted policy could not be loaded or saved safely.'**
  String get entryAgentsPolicyError;

  /// No description provided for @entryAgentsAccessNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get entryAgentsAccessNever;

  /// No description provided for @entryAgentsAccessDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get entryAgentsAccessDiscovery;

  /// No description provided for @entryAgentsAccessGrantValue.
  ///
  /// In en, this message translates to:
  /// **'Grant: value'**
  String get entryAgentsAccessGrantValue;

  /// No description provided for @entryAgentsAccessGrantDerived.
  ///
  /// In en, this message translates to:
  /// **'Grant: derived only'**
  String get entryAgentsAccessGrantDerived;

  /// No description provided for @entryAgentsAccessGrantRuntime.
  ///
  /// In en, this message translates to:
  /// **'Grant: runtime only'**
  String get entryAgentsAccessGrantRuntime;

  /// No description provided for @entryChangesSaved.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get entryChangesSaved;

  /// Section heading for the delete entry button at the bottom of the Details tab
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get entryDangerZone;

  /// Title of the delete entry confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Entry?'**
  String get entryDeleteTitle;

  /// Body of the delete entry confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete this entry and its encrypted data. This cannot be undone.'**
  String get entryDeleteConfirm;

  /// Destructive button label in the delete entry dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Entry'**
  String get entryDeleteAction;

  /// Button label while the delete request is in flight
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get entryDeleting;

  /// Label above the entry-type dropdown on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Entry type'**
  String get entryTypeLabel;

  /// Dropdown option for the Key entry type — single secret value
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get entryTypeKey;

  /// Dropdown option for the Credential entry type — username + password
  ///
  /// In en, this message translates to:
  /// **'Credential'**
  String get entryTypeCredential;

  /// No description provided for @entryTypeCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit card'**
  String get entryTypeCreditCard;

  /// Label for the entry name input field
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get entryLabelLabel;

  /// Placeholder text inside the entry label input field
  ///
  /// In en, this message translates to:
  /// **'e.g. Stripe API Key'**
  String get entryLabelHint;

  /// Label for the optional entry description input field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get entryDescriptionLabel;

  /// Label for the secret value input field on a Key entry
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get entryValueLabel;

  /// Label for the username input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get entryUsernameLabel;

  /// Label for the password input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get entryPasswordLabel;

  /// Label for the optional URL input field on a Credential entry
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get entryUrlLabel;

  /// Validation error shown below the URL field when the value is not a valid URL
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL (e.g. stripe.com or https://stripe.com)'**
  String get entryUrlInvalid;

  /// Label for the optional notes input field on every entry
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get entryNotesLabel;

  /// Reassurance shown above the save button on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Encrypted on-device with XSalsa20-Poly1305 before upload'**
  String get entryEncryptionNotice;

  /// No description provided for @entryDiscoverUsername.
  ///
  /// In en, this message translates to:
  /// **'Let agents discover the username'**
  String get entryDiscoverUsername;

  /// No description provided for @entryDiscoverDomain.
  ///
  /// In en, this message translates to:
  /// **'Let agents discover the URL domain'**
  String get entryDiscoverDomain;

  /// Placeholder for the search input on the Entries tab
  ///
  /// In en, this message translates to:
  /// **'Search entries…'**
  String get entrySearchHint;

  /// Empty-state title shown on the Entries tab when no entries exist yet
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get entryEmpty;

  /// Empty-state subtitle presenting manual creation and password-manager import
  ///
  /// In en, this message translates to:
  /// **'Add an entry manually or import from another password manager.'**
  String get entryEmptyAdd;

  /// AppBar action label on the Add Entry page
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get entrySaveAction;

  /// Loading label shown on the save button while the entry is being created
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get entrySaving;

  /// Error shown when the backend returns 404 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'This entry no longer exists.'**
  String get entryErrorNotFound;

  /// Error shown when the backend returns 403 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get entryErrorForbidden;

  /// Error shown when the backend returns 400 for an entry operation
  ///
  /// In en, this message translates to:
  /// **'Some fields are invalid. Please review and try again.'**
  String get entryErrorValidation;

  /// Error shown when entry encryption or decryption fails
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t decrypt this entry. Lock and unlock your vault, then try again.'**
  String get entryErrorCrypto;

  /// Generic fallback error for entry operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get entryErrorUnknown;

  /// Button that switches the read-only entry detail into edit mode
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get entryEditAction;

  /// No description provided for @entryShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get entryShowMore;

  /// No description provided for @entryShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get entryShowLess;

  /// Snackbar after copying a specific entry field (field = localized field name)
  ///
  /// In en, this message translates to:
  /// **'{field} copied to clipboard'**
  String entryCopiedField(String field);

  /// Snackbar confirmation shown after copying an entry field or secret
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get entryCopied;

  /// Entry type option — an executable script with credential references
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get entryTypeScript;

  /// Section heading for user-defined custom fields on an entry
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get entryCustomFieldsLabel;

  /// Button that appends a new custom field to the entry form
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get entryAddFieldAction;

  /// Label for the name input of a custom field
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get entryFieldNameLabel;

  /// Placeholder for the custom field name input
  ///
  /// In en, this message translates to:
  /// **'e.g. Recovery email'**
  String get entryFieldNameHint;

  /// Label for the value input of a custom field
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get entryFieldValueLabel;

  /// Label for the custom field type selector
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get entryFieldTypeLabel;

  /// Custom field type — plain visible text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get entryFieldTypeText;

  /// Custom field type — a concealed value masked until revealed
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get entryFieldTypeConcealed;

  /// Custom field type — a time-based one-time password (TOTP)
  ///
  /// In en, this message translates to:
  /// **'One-time code'**
  String get entryFieldTypeTotp;

  /// Tooltip for the button that deletes a custom field
  ///
  /// In en, this message translates to:
  /// **'Remove field'**
  String get entryFieldRemove;

  /// Tooltip for the drag handle that reorders custom fields
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get entryFieldReorder;

  /// Inline validation shown when a custom field has a value but no name
  ///
  /// In en, this message translates to:
  /// **'Add a name for this field'**
  String get entryFieldNameRequired;

  /// Title of the TOTP setup bottom sheet
  ///
  /// In en, this message translates to:
  /// **'One-time code'**
  String get totpSetupTitle;

  /// Button that opens the camera to scan an authenticator QR code
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get totpScanQr;

  /// Divider between the scan-QR option and manual TOTP entry
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get totpOr;

  /// Label for the input that accepts an otpauth:// URI or a base32 secret
  ///
  /// In en, this message translates to:
  /// **'Setup key'**
  String get totpSetupKeyLabel;

  /// Placeholder for the TOTP setup key input
  ///
  /// In en, this message translates to:
  /// **'otpauth://… or base32 secret'**
  String get totpSetupKeyHint;

  /// Label for the optional TOTP issuer name
  ///
  /// In en, this message translates to:
  /// **'Issuer (optional)'**
  String get totpIssuerLabel;

  /// Label for the optional TOTP account name
  ///
  /// In en, this message translates to:
  /// **'Account (optional)'**
  String get totpAccountLabel;

  /// Inline validation when the TOTP setup key cannot be parsed
  ///
  /// In en, this message translates to:
  /// **'Enter a valid otpauth:// key or base32 secret'**
  String get totpInvalidKey;

  /// Instruction shown on the QR scanner screen
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the authenticator QR code'**
  String get totpScanInstruction;

  /// App bar title of the TOTP QR scanner screen
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get totpScannerTitle;

  /// Message shown when camera permission is denied for QR scanning
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Enable it in Settings, or paste the setup key instead.'**
  String get totpCameraDenied;

  /// Button that opens the OS settings to grant camera permission
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get totpCameraOpenSettings;

  /// Status shown on a TOTP field once a secret is set
  ///
  /// In en, this message translates to:
  /// **'One-time code configured'**
  String get totpConfigured;

  /// Button that replaces an already-configured TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get totpReplaceSecret;

  /// Snackbar after copying a live TOTP code
  ///
  /// In en, this message translates to:
  /// **'One-time code copied'**
  String get totpCodeCopied;

  /// Shown when a stored TOTP secret cannot generate a code
  ///
  /// In en, this message translates to:
  /// **'Invalid code secret'**
  String get totpInvalidConfigured;

  /// Label for the script body input
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get entryScriptLabel;

  /// Placeholder for the script body input
  ///
  /// In en, this message translates to:
  /// **'#!/usr/bin/env bash\\n…'**
  String get entryScriptHint;

  /// Label for the script interpreter selector
  ///
  /// In en, this message translates to:
  /// **'Interpreter'**
  String get entryInterpreterLabel;

  /// Section heading for a script's environment-variable references
  ///
  /// In en, this message translates to:
  /// **'Credential references'**
  String get entryScriptRefsLabel;

  /// Section heading for a script's injected credential references
  ///
  /// In en, this message translates to:
  /// **'Injected vault data'**
  String get entryInjectedDataLabel;

  /// Explains what credential references do on a script entry
  ///
  /// In en, this message translates to:
  /// **'Map an environment variable to a field on another entry.'**
  String get entryScriptRefsHint;

  /// No description provided for @entryScriptParametersLabel.
  ///
  /// In en, this message translates to:
  /// **'CLI parameters'**
  String get entryScriptParametersLabel;

  /// No description provided for @entryScriptParameterAdd.
  ///
  /// In en, this message translates to:
  /// **'Add parameter'**
  String get entryScriptParameterAdd;

  /// No description provided for @entryScriptParameterName.
  ///
  /// In en, this message translates to:
  /// **'Parameter name'**
  String get entryScriptParameterName;

  /// No description provided for @entryScriptParameterNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. team_id'**
  String get entryScriptParameterNameHint;

  /// No description provided for @entryScriptParameterDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get entryScriptParameterDescription;

  /// No description provided for @entryScriptParameterType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get entryScriptParameterType;

  /// No description provided for @entryScriptParameterRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get entryScriptParameterRequired;

  /// No description provided for @entryScriptParameterRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove parameter'**
  String get entryScriptParameterRemove;

  /// No description provided for @entryScriptParameterTypeString.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get entryScriptParameterTypeString;

  /// No description provided for @entryScriptParameterTypeInteger.
  ///
  /// In en, this message translates to:
  /// **'Integer'**
  String get entryScriptParameterTypeInteger;

  /// No description provided for @entryScriptParameterTypeNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get entryScriptParameterTypeNumber;

  /// No description provided for @entryScriptParameterTypeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Boolean'**
  String get entryScriptParameterTypeBoolean;

  /// No description provided for @entryScriptReturnResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Return result to the Agent'**
  String get entryScriptReturnResultLabel;

  /// No description provided for @entryScriptReturnResultHint.
  ///
  /// In en, this message translates to:
  /// **'The script\'s standard output becomes available to the Agent or LLM. Secrets remain injected locally and must not be printed.'**
  String get entryScriptReturnResultHint;

  /// No description provided for @entryScriptImpactTitle.
  ///
  /// In en, this message translates to:
  /// **'Agents will receive this change'**
  String get entryScriptImpactTitle;

  /// No description provided for @entryScriptImpactMessage.
  ///
  /// In en, this message translates to:
  /// **'This Script is available to {effective} Agents: {direct} directly and {full} through FULL Exec access. Saving refreshes their executable package. Newly referenced secrets become available only inside local execution.'**
  String entryScriptImpactMessage(int effective, int direct, int full);

  /// No description provided for @entryScriptImpactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Save and refresh access'**
  String get entryScriptImpactConfirm;

  /// No description provided for @entryScriptImpactCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not verify which Agents use this Script. Nothing was saved.'**
  String get entryScriptImpactCheckFailed;

  /// Button that appends a new credential reference to a script
  ///
  /// In en, this message translates to:
  /// **'Add reference'**
  String get entryAddRefAction;

  /// Label for the environment variable name of a script reference
  ///
  /// In en, this message translates to:
  /// **'Environment variable'**
  String get entryRefEnvLabel;

  /// Placeholder for the environment variable name
  ///
  /// In en, this message translates to:
  /// **'e.g. GITHUB_TOKEN'**
  String get entryRefEnvHint;

  /// Label for the target entry of a script credential reference
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get entryRefEntryLabel;

  /// Label for the target field of a script credential reference
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get entryRefFieldLabel;

  /// Placeholder for the entry autocomplete in a script reference
  ///
  /// In en, this message translates to:
  /// **'Select an entry'**
  String get entryRefEntryHint;

  /// Tooltip for the button that deletes a script credential reference
  ///
  /// In en, this message translates to:
  /// **'Remove reference'**
  String get entryRefRemove;

  /// Empty state for a script entry detail with no body
  ///
  /// In en, this message translates to:
  /// **'No script yet'**
  String get entryScriptEmpty;

  /// Empty state when a script has no credential references
  ///
  /// In en, this message translates to:
  /// **'No credential references'**
  String get entryRefsEmpty;

  /// Shown when the encrypted payload exceeds the backend's size limit
  ///
  /// In en, this message translates to:
  /// **'This entry is too large. Shorten the script or remove some fields.'**
  String get entryTooLarge;

  /// Uppercase title of the script security warning box
  ///
  /// In en, this message translates to:
  /// **'EXEC-ONLY DELIVERY'**
  String get entryScriptExecOnlyTitle;

  /// Calm exec-only annotation shown below the script editor
  ///
  /// In en, this message translates to:
  /// **'Runs on the agent via palladin exec — agents execute it, never read it.'**
  String get entryScriptExecOnlyNotice;

  /// Script editor footer — interpreter name and line count
  ///
  /// In en, this message translates to:
  /// **'{interpreter} · {lines, plural, one{1 line} other{{lines} lines}}'**
  String entryScriptFooter(String interpreter, int lines);

  /// Custom field type — multi-line monospace text (configs, keys)
  ///
  /// In en, this message translates to:
  /// **'Multiline'**
  String get entryFieldTypeMultiline;

  /// Hint next to the Text field type in the add-field menu
  ///
  /// In en, this message translates to:
  /// **'single line'**
  String get entryFieldTypeTextHint;

  /// Hint next to the Multiline field type in the add-field menu
  ///
  /// In en, this message translates to:
  /// **'notes, config'**
  String get entryFieldTypeMultilineHint;

  /// Hint next to the Hidden field type in the add-field menu
  ///
  /// In en, this message translates to:
  /// **'masked'**
  String get entryFieldTypeConcealedHint;

  /// Row-menu toggle that exposes a field to agents as discovery metadata
  ///
  /// In en, this message translates to:
  /// **'Visible to agents'**
  String get entryFieldAgentVisible;

  /// Tooltip explaining the agent-visible field indicator
  ///
  /// In en, this message translates to:
  /// **'Visible to agents in your organization — shown in agent discovery without a grant. Only for non-secret helper info.'**
  String get entryFieldAgentVisibleTip;

  /// No description provided for @entryFieldAgentVisibleEnableTip.
  ///
  /// In en, this message translates to:
  /// **'Hidden from agents in Discovery. Tap to make this non-secret field discoverable.'**
  String get entryFieldAgentVisibleEnableTip;

  /// No description provided for @entryFieldAgentVisibleDisableTip.
  ///
  /// In en, this message translates to:
  /// **'Visible to agents in Discovery. Tap to hide this field from Discovery.'**
  String get entryFieldAgentVisibleDisableTip;

  /// No description provided for @entryFieldAgentDiscoveryVisible.
  ///
  /// In en, this message translates to:
  /// **'Visible in Agent Discovery'**
  String get entryFieldAgentDiscoveryVisible;

  /// No description provided for @entryFieldAgentDiscoveryHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden from Agent Discovery'**
  String get entryFieldAgentDiscoveryHidden;

  /// Trailing state for an enabled toggle in a field menu
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get entryFieldOn;

  /// Trailing state for a disabled toggle in a field menu
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get entryFieldOff;

  /// Field menu action — move the field one position up
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get entryFieldMoveUp;

  /// Field menu action — move the field one position down
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get entryFieldMoveDown;

  /// Tooltip for the per-field overflow (⋯) button
  ///
  /// In en, this message translates to:
  /// **'Field options'**
  String get entryFieldMenu;

  /// Subtle hint appended to the Label and Description field captions
  ///
  /// In en, this message translates to:
  /// **'visible to agents'**
  String get entryVisibleToAgents;

  /// Section header for the entry's TOTP two-factor code
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get totpSectionTitle;

  /// Explanation shown in the empty 2FA section
  ///
  /// In en, this message translates to:
  /// **'Add a time-based code (TOTP) to autofill 2FA for this login.'**
  String get totpEmptyHint;

  /// Button that starts TOTP setup in the empty 2FA section
  ///
  /// In en, this message translates to:
  /// **'Add 2FA'**
  String get totpAdd;

  /// Subtitle on a configured 2FA card
  ///
  /// In en, this message translates to:
  /// **'rotates every 30 s'**
  String get totpRotates;

  /// 2FA card menu action — copy the current one-time code
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get totpCopyCode;

  /// 2FA card menu action — delete the TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Remove 2FA'**
  String get totpRemove;

  /// Ghost affordance that reveals the optional Notes field
  ///
  /// In en, this message translates to:
  /// **'Add notes'**
  String get entryAddNotes;

  /// Title of the dedicated settings screen (organization details)
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// Label for the settings-drawer item that opens the organization settings screen
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get settingsManageOrganization;

  /// Label for the editable organization name input field
  ///
  /// In en, this message translates to:
  /// **'Organization name'**
  String get settingsOrgNameLabel;

  /// Placeholder text for the organization name input field
  ///
  /// In en, this message translates to:
  /// **'Enter organization name'**
  String get settingsOrgNameHint;

  /// Label for the save button on the organization form
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// Snackbar confirmation shown after a successful organization rename
  ///
  /// In en, this message translates to:
  /// **'Organization name updated.'**
  String get settingsOrgSaved;

  /// Label for the settings-drawer item that opens the standalone API keys screen
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get settingsApiKeys;

  /// Label for the retry button on settings error states
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsRetry;

  /// Error shown when the backend returns 404 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this resource.'**
  String get settingsErrorNotFound;

  /// Error shown when the backend returns 403 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to perform this action.'**
  String get settingsErrorForbidden;

  /// Error shown when the backend returns 400 for a settings operation
  ///
  /// In en, this message translates to:
  /// **'Please check the form and try again.'**
  String get settingsErrorValidation;

  /// Generic fallback error for settings operations
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get settingsErrorUnknown;

  /// Title of the standalone API keys list screen
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get apiKeysScreenTitle;

  /// Empty-state title shown when the organization has no API keys
  ///
  /// In en, this message translates to:
  /// **'No API keys yet'**
  String get apiKeysEmpty;

  /// Empty-state supporting copy for the API keys list
  ///
  /// In en, this message translates to:
  /// **'Generate a key to connect your first agent.'**
  String get apiKeysEmptyHint;

  /// Status badge label for an active API key
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get apiKeysStatusActive;

  /// Status badge label for a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeysStatusRevoked;

  /// Label for the retry button on API keys error states
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get apiKeysRetry;

  /// Tooltip / heading for the generate-API-key action and sheet
  ///
  /// In en, this message translates to:
  /// **'Generate API key'**
  String get apiKeysGenerate;

  /// Submit-button label in the generate-API-key sheet
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get apiKeysGenerateAction;

  /// Loading label shown on the generate button while the key is being created
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get apiKeysGenerating;

  /// Label for the API key name input field in the generate sheet
  ///
  /// In en, this message translates to:
  /// **'Key name'**
  String get apiKeysNameLabel;

  /// Placeholder text for the API key name input field
  ///
  /// In en, this message translates to:
  /// **'e.g. Production agent'**
  String get apiKeysNameHint;

  /// Title of the one-time secret reveal step in the generate sheet
  ///
  /// In en, this message translates to:
  /// **'API Key Created'**
  String get apiKeysSecretTitle;

  /// Warning shown above the one-time plaintext API key secret
  ///
  /// In en, this message translates to:
  /// **'Save this key now — it will never be shown again.'**
  String get apiKeysSecretWarning;

  /// Label for the copy-to-clipboard button next to the API key secret
  ///
  /// In en, this message translates to:
  /// **'Copy key'**
  String get apiKeysCopyKey;

  /// Snackbar confirmation shown after copying the API key secret
  ///
  /// In en, this message translates to:
  /// **'API key copied to clipboard.'**
  String get apiKeysKeyCopied;

  /// Generic snackbar confirmation shown after copying a command, message, or link
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get apiKeysCopied;

  /// Header of the collapsible section that shows how to connect an agent with the new key
  ///
  /// In en, this message translates to:
  /// **'Connect your agent'**
  String get apiKeysConnectTitle;

  /// Label for the editable agent-name field in the connect section
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get apiKeysAgentNameLabel;

  /// Hint above the CLI install command in the connect section
  ///
  /// In en, this message translates to:
  /// **'Don\'t have the CLI? Install it:'**
  String get apiKeysConnectInstall;

  /// Label for the tap-to-copy documentation link in the connect section
  ///
  /// In en, this message translates to:
  /// **'Copy docs link'**
  String get apiKeysConnectDocs;

  /// Header of the collapsible section with a ready-to-send message for the agent
  ///
  /// In en, this message translates to:
  /// **'Message for your agent'**
  String get apiKeysAgentMessageTitle;

  /// Copyable message a user can send to their agent after connecting it
  ///
  /// In en, this message translates to:
  /// **'{name}, I\'ve connected you to Palladin for secure access to my credentials. Learn how to create and use your Palladin skill here: {docs} — or browse ready-made skills in the marketplace: {market}.'**
  String apiKeysAgentMessageBody(String name, String docs, String market);

  /// Label for the button that dismisses the secret reveal step
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get apiKeysDone;

  /// Generic cancel label used by API key dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get apiKeysCancel;

  /// Label for the action that revokes an API key
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get apiKeysRevoke;

  /// Title of the revoke-API-key confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Revoke API key?'**
  String get apiKeysRevokeConfirmTitle;

  /// Body of the revoke-API-key confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Agents using \"{name}\" will lose access immediately. This cannot be undone.'**
  String apiKeysRevokeConfirmBody(String name);

  /// Fallback AppBar title on the API key detail screen while the key is loading
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeysDetailTitle;

  /// Message shown on the API key detail screen when the key id cannot be resolved
  ///
  /// In en, this message translates to:
  /// **'This API key no longer exists.'**
  String get apiKeysDetailNotFound;

  /// Label of the Details tab on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get apiKeysTabDetails;

  /// Label of the Agents tab on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get apiKeysTabAgents;

  /// Label for the masked key row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get apiKeysDetailKey;

  /// Label for the created-date row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get apiKeysDetailCreatedAt;

  /// Label for the revoked-date row on the API key detail screen
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeysDetailRevokedAt;

  /// Button label to re-activate a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get apiKeysActivate;

  /// Button label while activation is in flight
  ///
  /// In en, this message translates to:
  /// **'Activating…'**
  String get apiKeysActivating;

  /// Button label to permanently delete a revoked API key
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get apiKeysDeletePermanently;

  /// Button label while delete is in flight
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get apiKeysDeleting;

  /// Title of the permanent-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete API key?'**
  String get apiKeysDeleteConfirmTitle;

  /// Body of the permanent-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\". This cannot be undone.'**
  String apiKeysDeleteConfirmBody(String name);

  /// Section header for the activate section on the revoked key detail page
  ///
  /// In en, this message translates to:
  /// **'ACTIVATE KEY'**
  String get apiKeysActivateZone;

  /// Subtitle in the activate section
  ///
  /// In en, this message translates to:
  /// **'Re-enable this key — agents using it will regain access immediately.'**
  String get apiKeysActivateHint;

  /// Count summary in the API keys screen AppBar subtitle
  ///
  /// In en, this message translates to:
  /// **'{total} keys · {active} active'**
  String apiKeysListSummary(int total, int active);

  /// Title of the agents list screen
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agentsScreenTitle;

  /// Count summary in the agents screen AppBar subtitle
  ///
  /// In en, this message translates to:
  /// **'{total} agents, {active} active'**
  String agentsListSummary(int total, int active);

  /// Empty-state title for the agents list
  ///
  /// In en, this message translates to:
  /// **'No agents yet'**
  String get agentsEmpty;

  /// Empty-state hint for the agents list
  ///
  /// In en, this message translates to:
  /// **'Connect your first agent using the CLI to get started'**
  String get agentsEmptyHint;

  /// Placeholder text for the agents search field
  ///
  /// In en, this message translates to:
  /// **'Search agents…'**
  String get agentsSearchHint;

  /// Shown when the search query returns no results
  ///
  /// In en, this message translates to:
  /// **'No agents match your search'**
  String get agentsSearchEmpty;

  /// Fallback display name for an agent with no name set
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get agentsUnnamed;

  /// Prompt shown in the split-view detail pane when no agent is selected
  ///
  /// In en, this message translates to:
  /// **'Select an agent to see its details'**
  String get agentsSplitPrompt;

  /// Agent status label — active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get agentsStatusActive;

  /// Agent status label — pending approval
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get agentsStatusPending;

  /// Agent status label — deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsStatusDeactivated;

  /// Prefix for the enrolled-date subtitle on an agent card
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsEnrolled;

  /// Prefix for the deactivated-date subtitle on an agent card
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsDeactivated;

  /// Prefix for the deactivated-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Deactivated on'**
  String get agentsDeactivatedOn;

  /// Prefix for the first-connected-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Connected on'**
  String get agentsConnectedOn;

  /// Prefix for the last-access-date in the agent card footer
  ///
  /// In en, this message translates to:
  /// **'Last access'**
  String get agentsLastAccess;

  /// Subtitle on a pending agent card
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get agentsPendingApproval;

  /// Generic title of the agent detail screen while loading
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentsDetailTitle;

  /// Shown when the requested agent does not exist
  ///
  /// In en, this message translates to:
  /// **'Agent not found'**
  String get agentsDetailNotFound;

  /// Label for the agent id row on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Id'**
  String get agentsDetailId;

  /// Label for the public key suffix row
  ///
  /// In en, this message translates to:
  /// **'Public Key'**
  String get agentsDetailPublicKey;

  /// Label for the date the agent first connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get agentsDetailCreatedAt;

  /// Label for the date the agent was approved
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsDetailEnrolledAt;

  /// Label for who approved the agent
  ///
  /// In en, this message translates to:
  /// **'Enrolled by'**
  String get agentsDetailEnrolledBy;

  /// Label for the date the agent was deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsDetailDeactivatedAt;

  /// Section header for the approve zone on a pending agent
  ///
  /// In en, this message translates to:
  /// **'APPROVE AGENT'**
  String get agentsApproveZone;

  /// Hint in the approve zone
  ///
  /// In en, this message translates to:
  /// **'Lets this agent browse vault and entry listings only — secret contents stay locked until you approve a request or grant access in advance.'**
  String get agentsApproveHint;

  /// Button label to approve a pending agent
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentsApprove;

  /// Button label while approval is in flight
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get agentsApproving;

  /// Section header for the deactivate danger zone
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get agentsDeactivateZone;

  /// Hint inside the deactivate danger zone
  ///
  /// In en, this message translates to:
  /// **'This agent will immediately lose access to all vaults'**
  String get agentsDeactivateHint;

  /// Button label to deactivate an active agent
  ///
  /// In en, this message translates to:
  /// **'Deactivate Agent'**
  String get agentsDeactivate;

  /// Button label while deactivation is in flight
  ///
  /// In en, this message translates to:
  /// **'Deactivating…'**
  String get agentsDeactivating;

  /// Section header for the reactivate zone on a deactivated agent
  ///
  /// In en, this message translates to:
  /// **'REACTIVATE'**
  String get agentsReactivateZone;

  /// Hint in the reactivate zone
  ///
  /// In en, this message translates to:
  /// **'Re-enable access for this agent'**
  String get agentsReactivateHint;

  /// Button label to reactivate a deactivated agent
  ///
  /// In en, this message translates to:
  /// **'Reactivate Agent'**
  String get agentsReactivate;

  /// Button label while reactivation is in flight
  ///
  /// In en, this message translates to:
  /// **'Reactivating…'**
  String get agentsReactivating;

  /// Title of the approve confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentsApproveConfirmTitle;

  /// Body of the approve confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Allow \"{name}\" to browse vault and entry listings? It still can\'t read any secret without your approval or a pre-granted access.'**
  String agentsApproveConfirmBody(String name);

  /// Title of the deactivate confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Deactivate Agent'**
  String get agentsDeactivateConfirmTitle;

  /// Body of the deactivate confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Deactivate \"{name}\"? It will immediately lose access.'**
  String agentsDeactivateConfirmBody(String name);

  /// Title of the agent edit screen
  ///
  /// In en, this message translates to:
  /// **'Edit Agent'**
  String get agentsEditTitle;

  /// Label for the agent display-name field
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get agentsEditName;

  /// Label for the agent description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get agentsEditDescription;

  /// Save button on the agent edit screen
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get agentsEditSave;

  /// Retry button on the agents error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get agentsRetry;

  /// Label / tooltip for the edit-agent action
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get agentsEditIcon;

  /// Title of the approve-agent form sheet
  ///
  /// In en, this message translates to:
  /// **'Approve Agent'**
  String get agentApproveTitle;

  /// Label for the optional agent name input in the approve form
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get agentNameLabel;

  /// Label for the agent type chip group in the approve form
  ///
  /// In en, this message translates to:
  /// **'Agent type'**
  String get agentTypeLabel;

  /// Label for the agent icon picker in the approve form
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get agentIconLabel;

  /// Agent type option — Open Claw
  ///
  /// In en, this message translates to:
  /// **'Open Claw'**
  String get agentTypeOpenClaw;

  /// Agent type option — Claude Code
  ///
  /// In en, this message translates to:
  /// **'Claude Code'**
  String get agentTypeClaudeCode;

  /// Agent type option — Hermes
  ///
  /// In en, this message translates to:
  /// **'Hermes'**
  String get agentTypeHermes;

  /// Agent type option — Cursor
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get agentTypeCursor;

  /// Agent type option — GitHub Copilot
  ///
  /// In en, this message translates to:
  /// **'GitHub Copilot'**
  String get agentTypeCopilot;

  /// Agent type option — Gemini
  ///
  /// In en, this message translates to:
  /// **'Gemini'**
  String get agentTypeGemini;

  /// Agent type option — OpenAI Codex
  ///
  /// In en, this message translates to:
  /// **'OpenAI Codex'**
  String get agentTypeCodex;

  /// Agent type option — Kimi Code
  ///
  /// In en, this message translates to:
  /// **'Kimi Code'**
  String get agentTypeKimiCode;

  /// Agent type option — Devin
  ///
  /// In en, this message translates to:
  /// **'Devin'**
  String get agentTypeDevin;

  /// Agent type option — Aider
  ///
  /// In en, this message translates to:
  /// **'Aider'**
  String get agentTypeAider;

  /// Agent type option — Cline
  ///
  /// In en, this message translates to:
  /// **'Cline'**
  String get agentTypeCline;

  /// Agent type option — Roo Code
  ///
  /// In en, this message translates to:
  /// **'Roo Code'**
  String get agentTypeRoo;

  /// Agent type option — Other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get agentTypeOther;

  /// Subtitle under the approve-agent dialog title
  ///
  /// In en, this message translates to:
  /// **'Optionally set a name, type, and icon before activating.'**
  String get agentApproveSetupHint;

  /// Placeholder for the agent name input on the approve form
  ///
  /// In en, this message translates to:
  /// **'e.g. Claude Code, Cursor'**
  String get agentNamePlaceholder;

  /// Tab label — agent details tab
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get agentsTabDetails;

  /// Tab label — agent grants tab
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get agentsTabGrants;

  /// Agent Grants tab — empty title
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get agentGrantsEmptyTitle;

  /// Agent Grants tab — empty hint
  ///
  /// In en, this message translates to:
  /// **'This agent has no grants. Add one to give it access to a vault or entry.'**
  String get agentGrantsEmptyHint;

  /// Tab label — agent logs tab
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get agentsTabLogs;

  /// Empty state for the agent grants tab
  ///
  /// In en, this message translates to:
  /// **'No active grants'**
  String get agentsGrantsEmpty;

  /// Empty state hint for the agent grants tab
  ///
  /// In en, this message translates to:
  /// **'This agent has not been granted access to any vault entries yet'**
  String get agentsGrantsEmptyHint;

  /// Timeline entry — agent first connected
  ///
  /// In en, this message translates to:
  /// **'First connected'**
  String get agentsLogsFirstConnected;

  /// Timeline entry — agent was enrolled / approved
  ///
  /// In en, this message translates to:
  /// **'Enrolled'**
  String get agentsLogsEnrolled;

  /// Timeline entry — agent was deactivated
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get agentsLogsDeactivated;

  /// Snackbar after saving agent edit changes
  ///
  /// In en, this message translates to:
  /// **'Agent saved'**
  String get agentsEditSaved;

  /// Placeholder for the agent type combobox in the approve form
  ///
  /// In en, this message translates to:
  /// **'Pick a preset or type a custom value'**
  String get agentTypePlaceholder;

  /// Accessibility label for the 'more' tile that opens the icon browser
  ///
  /// In en, this message translates to:
  /// **'More icons'**
  String get agentIconMore;

  /// Header of the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Browse icons'**
  String get agentIconBrowserTitle;

  /// Label above the color swatches in the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get agentIconColorLabel;

  /// Confirm button label inside the icon browser modal
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get agentIconChoose;

  /// No description provided for @publicAssetSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Website icons'**
  String get publicAssetSearchTitle;

  /// No description provided for @publicAssetSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search brands or domains'**
  String get publicAssetSearchHint;

  /// No description provided for @publicAssetSearchAction.
  ///
  /// In en, this message translates to:
  /// **'Search website icons'**
  String get publicAssetSearchAction;

  /// Fallback type label on the agent card when no type is set
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get agentsTypeUnknown;

  /// Label for the last known IP address of the agent
  ///
  /// In en, this message translates to:
  /// **'Last IP'**
  String get agentsDetailLastIp;

  /// Label for the last known hostname of the agent
  ///
  /// In en, this message translates to:
  /// **'Last Hostname'**
  String get agentsDetailLastHostname;

  /// Title of the grant-management list screen
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get grantsScreenTitle;

  /// Status filter chip — show grants of every status
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get grantsFilterAll;

  /// Retry button on the grants error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get grantsRetry;

  /// Empty-state title on the grants list
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get grantsEmpty;

  /// Empty-state hint on the grants list
  ///
  /// In en, this message translates to:
  /// **'Grants appear here when an agent requests access to this vault.'**
  String get grantsEmptyHint;

  /// Revoke action button label
  ///
  /// In en, this message translates to:
  /// **'Revoke grant'**
  String get grantsRevoke;

  /// Title of the revoke confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'Revoke grant?'**
  String get grantsRevokeConfirmTitle;

  /// Body of the revoke confirmation sheet
  ///
  /// In en, this message translates to:
  /// **'{agentName} will immediately lose access. This cannot be undone.'**
  String grantsRevokeConfirmBody(String agentName);

  /// Label for the optional revoke reason field
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get grantsRevokeReasonLabel;

  /// Hint for the optional revoke reason field
  ///
  /// In en, this message translates to:
  /// **'Why are you revoking this grant?'**
  String get grantsRevokeReasonHint;

  /// One-line target summary on a grant card
  ///
  /// In en, this message translates to:
  /// **'Access to {target}'**
  String grantCardTarget(String target);

  /// Fallback when a granular grant's entry label is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown entry'**
  String get grantEntryUnknown;

  /// Fallback display name for an agent without a name
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get grantUnnamedAgent;

  /// Grant status label — pending approval
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get grantStatusPending;

  /// Grant status label — active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get grantStatusActive;

  /// Grant status label — denied
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get grantStatusDenied;

  /// Grant status label — revoked
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get grantStatusRevoked;

  /// Grant status label — expired
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get grantStatusExpired;

  /// Grant status label — query limit exhausted
  ///
  /// In en, this message translates to:
  /// **'Consumed'**
  String get grantStatusConsumed;

  /// Terminal grant status: replaced by a FULL Vault grant
  ///
  /// In en, this message translates to:
  /// **'Superseded'**
  String get grantStatusSuperseded;

  /// Grant scope label — full vault access
  ///
  /// In en, this message translates to:
  /// **'All entries'**
  String get grantScopeFull;

  /// Grant scope label — granular single-entry access
  ///
  /// In en, this message translates to:
  /// **'Single entry'**
  String get grantScopeGranular;

  /// No description provided for @grantScopeScriptExecution.
  ///
  /// In en, this message translates to:
  /// **'Whole Script execution'**
  String get grantScopeScriptExecution;

  /// No description provided for @grantAccessScriptTrustTitle.
  ///
  /// In en, this message translates to:
  /// **'ONE SCRIPT EXECUTION GRANT'**
  String get grantAccessScriptTrustTitle;

  /// No description provided for @grantAccessScriptTrustBody.
  ///
  /// In en, this message translates to:
  /// **'This grants Exec access to the complete Script package: source plus every referenced field, resolved locally in one request. Adding a reference later expands what this Agent can use. CLI parameter values never reach the backend.'**
  String get grantAccessScriptTrustBody;

  /// Approvals screen segment — pending approval inbox
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalSegmentPending;

  /// Approvals screen segment — org-wide grant history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get approvalSegmentHistory;

  /// Search placeholder on the Approvals history segment
  ///
  /// In en, this message translates to:
  /// **'Search grants…'**
  String get approvalHistorySearchHint;

  /// Empty state title for the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get approvalHistoryEmpty;

  /// Empty state hint for the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'Granted, expired and revoked access will appear here.'**
  String get approvalHistoryEmptyHint;

  /// Clears the status filter on the Approvals history feed
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get approvalHistoryFilterClear;

  /// Subtitle under the agent name on a pending-approval card
  ///
  /// In en, this message translates to:
  /// **'requests access'**
  String get approvalPendingRequestsAccess;

  /// Pending card row label — when the request was made
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get approvalPendingRowRequested;

  /// Org grant card row label — target vault (FULL grant)
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get orgGrantRowVault;

  /// Org grant card row label — target entry (granular grant)
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get orgGrantRowEntry;

  /// Org grant card row label — actor who last acted on the grant
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get orgGrantRowActor;

  /// Org grant card row label — access policy summary
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get orgGrantRowAccess;

  /// Org grant card row label — permitted methods
  ///
  /// In en, this message translates to:
  /// **'Methods'**
  String get orgGrantRowMethods;

  /// Org grant card row label — agent's access request reason
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get orgGrantRowReason;

  /// Org grant card row label — owner's deny reason
  ///
  /// In en, this message translates to:
  /// **'Deny reason'**
  String get orgGrantRowDenyReason;

  /// No description provided for @orgGrantSupersededReason.
  ///
  /// In en, this message translates to:
  /// **'Replaced by a FULL grant'**
  String get orgGrantSupersededReason;

  /// Org grant card row label — owner's revoke reason
  ///
  /// In en, this message translates to:
  /// **'Revoke reason'**
  String get orgGrantRowRevokeReason;

  /// Fallback actor name when no user acted (e.g. automatic expiry)
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get orgGrantActorSystem;

  /// Access summary — no usage or time limit
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get orgGrantUnlimited;

  /// Access summary — remaining query uses for a use-limited grant
  ///
  /// In en, this message translates to:
  /// **'{left} of {limit} uses left'**
  String orgGrantUsesLeft(int left, int limit);

  /// Access summary — absolute expiry date for a time-limited grant
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String orgGrantExpiresOn(String date);

  /// Footer on a terminal grant whose agent already holds active coverage
  ///
  /// In en, this message translates to:
  /// **'Active in a newer grant'**
  String get orgGrantAlreadyActive;

  /// Action that opens the newer active grant covering terminal history
  ///
  /// In en, this message translates to:
  /// **'Show active grant'**
  String get orgGrantShowActive;

  /// Footer when terminal access cannot be re-granted because the Agent or target is unavailable
  ///
  /// In en, this message translates to:
  /// **'Grant again unavailable'**
  String get orgGrantRegrantUnavailable;

  /// Action opening the Agent associated with terminal grant history
  ///
  /// In en, this message translates to:
  /// **'View agent'**
  String get orgGrantViewAgent;

  /// Fallback action opening the Vault when terminal grant history has no Agent
  ///
  /// In en, this message translates to:
  /// **'View vault'**
  String get orgGrantViewVault;

  /// Action on a pending grant card that opens the Inbox approval queue
  ///
  /// In en, this message translates to:
  /// **'Review request'**
  String get orgGrantReviewRequest;

  /// Title of the grant detail screen
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grantDetailTitle;

  /// Detail field label — grant scope
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get grantDetailScope;

  /// Detail field label — target entry
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get grantDetailEntry;

  /// Detail field label — expiry / use limit
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get grantDetailExpiry;

  /// Detail section label — agent-supplied reason
  ///
  /// In en, this message translates to:
  /// **'Agent\'s reason'**
  String get grantDetailReason;

  /// Detail field label — request timestamp
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get grantDetailRequested;

  /// Detail field label — approval timestamp
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get grantDetailApproved;

  /// Approval timestamp with approver name
  ///
  /// In en, this message translates to:
  /// **'{date} by {name}'**
  String grantDetailApprovedBy(String date, String name);

  /// Detail field label — revoke timestamp
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get grantDetailRevoked;

  /// Expiry line — absolute TTL
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String grantDetailExpiresAt(String date);

  /// Expiry line — use-limited grant
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} uses'**
  String grantDetailUsesLimit(int used, int limit);

  /// Expiry line — unbounded grant
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get grantDetailNoExpiry;

  /// Error — 404 on grants
  ///
  /// In en, this message translates to:
  /// **'This grant no longer exists.'**
  String get grantsErrorNotFound;

  /// Error — 403 on grants
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage grants.'**
  String get grantsErrorForbidden;

  /// Error — 400/409 on grants
  ///
  /// In en, this message translates to:
  /// **'The request was rejected. Please check and try again.'**
  String get grantsErrorValidation;

  /// Error — network failure on grants
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get grantsErrorNetwork;

  /// Error — on-device crypto failure during approval
  ///
  /// In en, this message translates to:
  /// **'Could not securely prepare the credential. Please try again.'**
  String get grantsErrorCrypto;

  /// Error — unexpected failure on grants
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get grantsErrorUnknown;

  /// Title of the cross-vault pending-grant approval inbox
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalInboxTitle;

  /// Empty-state title on the approval inbox
  ///
  /// In en, this message translates to:
  /// **'Nothing to approve'**
  String get approvalInboxEmpty;

  /// Empty-state hint on the approval inbox
  ///
  /// In en, this message translates to:
  /// **'When an agent requests access to a credential, the request shows up here for you to approve or deny.'**
  String get approvalInboxEmptyHint;

  /// Retry button on the approval inbox error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get approvalRetry;

  /// One-line summary on a pending-grant card
  ///
  /// In en, this message translates to:
  /// **'Wants {entry} in {vault}'**
  String approvalCardRequest(String entry, String vault);

  /// Title of the approve/deny screen for a single grant
  ///
  /// In en, this message translates to:
  /// **'Review request'**
  String get approvalScreenTitle;

  /// Label for the requested entry in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get approvalSummaryEntry;

  /// Label for the vault in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get approvalSummaryVault;

  /// Label for the agent-supplied reason in the approval summary
  ///
  /// In en, this message translates to:
  /// **'Agent\'s reason'**
  String get approvalSummaryReason;

  /// Fallback display name for an agent without a name
  ///
  /// In en, this message translates to:
  /// **'Unnamed agent'**
  String get approvalUnnamedAgent;

  /// Fallback when the requested entry label is missing
  ///
  /// In en, this message translates to:
  /// **'this credential'**
  String get approvalEntryUnknown;

  /// Fallback when the vault name is missing
  ///
  /// In en, this message translates to:
  /// **'a vault'**
  String get approvalVaultUnknown;

  /// Section title for the XOR expiry/use-count limit picker
  ///
  /// In en, this message translates to:
  /// **'Access limit'**
  String get approvalLimitSectionTitle;

  /// Hint under the access-limit section title
  ///
  /// In en, this message translates to:
  /// **'Choose how long this access lasts — by time or by number of uses.'**
  String get approvalLimitSectionHint;

  /// Segmented toggle option — time-to-live limit
  ///
  /// In en, this message translates to:
  /// **'Expires after'**
  String get approvalLimitExpiry;

  /// Segmented toggle option — use-count limit
  ///
  /// In en, this message translates to:
  /// **'Number of uses'**
  String get approvalLimitUses;

  /// Text field label for the maximum number of uses
  ///
  /// In en, this message translates to:
  /// **'Max uses'**
  String get approvalLimitUsesLabel;

  /// Approve button label
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approvalApprove;

  /// Section title for the deny action
  ///
  /// In en, this message translates to:
  /// **'Deny instead'**
  String get approvalDenySectionTitle;

  /// Label for the optional deny reason field
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get approvalDenyReasonLabel;

  /// Hint for the optional deny reason field
  ///
  /// In en, this message translates to:
  /// **'Why are you denying this request?'**
  String get approvalDenyReasonHint;

  /// Deny button label
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get approvalDeny;

  /// Cancel button on approval sheets
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get approvalCancel;

  /// Title of the approve bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Approve request'**
  String get approvalApproveTitle;

  /// Approve subtitle fragment — leading verb before the agent name
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get approvalApproveSubGrant;

  /// Approve subtitle fragment — between agent and entry
  ///
  /// In en, this message translates to:
  /// **'access to'**
  String get approvalApproveSubAccessTo;

  /// Approve subtitle fragment — between entry and vault
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get approvalApproveSubIn;

  /// Label above the access policy selector
  ///
  /// In en, this message translates to:
  /// **'Access type'**
  String get approvalAccessType;

  /// Label above the grant methods selector
  ///
  /// In en, this message translates to:
  /// **'How the agent may use it'**
  String get approvalMethodsLegend;

  /// Title of the amber warning box shown when the plaintext get method is selected
  ///
  /// In en, this message translates to:
  /// **'Warning Zone'**
  String get approvalMethodWarningZone;

  /// Error when no method is selected on approve
  ///
  /// In en, this message translates to:
  /// **'Select at least one method.'**
  String get approvalMethodNoneSelected;

  /// Label for the get method
  ///
  /// In en, this message translates to:
  /// **'Get (plaintext)'**
  String get approvalMethodGetLabel;

  /// Warning shown for the get method
  ///
  /// In en, this message translates to:
  /// **'The secret enters the agent\'s context — on a hosted LLM it may leave the device.'**
  String get approvalMethodGetWarning;

  /// Label for the exec method
  ///
  /// In en, this message translates to:
  /// **'Exec'**
  String get approvalMethodExecLabel;

  /// Label for the inject method
  ///
  /// In en, this message translates to:
  /// **'Inject'**
  String get approvalMethodInjectLabel;

  /// Approve button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get approvalApproving;

  /// Access policy option — time-limited (TTL)
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get approvalPolicyTime;

  /// Access policy option — use-count limited
  ///
  /// In en, this message translates to:
  /// **'Uses'**
  String get approvalPolicyUses;

  /// Access policy option — unlimited / until revoked
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get approvalPolicyLifetime;

  /// Hint shown when the lifetime access policy is selected
  ///
  /// In en, this message translates to:
  /// **'The agent keeps access until you revoke it.'**
  String get approvalLifetimeHint;

  /// Label for the expiry date picker field
  ///
  /// In en, this message translates to:
  /// **'Expires on'**
  String get approvalExpiresOnLabel;

  /// Quick-pick minutes chip label
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String approvalQuickMinutes(int count);

  /// Quick-pick hours chip label
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String approvalQuickHours(int count);

  /// Chip that opens the custom date/time picker
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get approvalQuickCustom;

  /// Relative expiry (minutes) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}m'**
  String approvalExpiresInMinutes(int count);

  /// Relative expiry (hours) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}h'**
  String approvalExpiresInHours(int count);

  /// Relative expiry (days) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}d'**
  String approvalExpiresInDays(int count);

  /// Relative expiry (months) in the approve summary
  ///
  /// In en, this message translates to:
  /// **'Expires in {count}mo'**
  String approvalExpiresInMonths(int count);

  /// Shown when the chosen expiry is in the past
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get approvalExpiredAlready;

  /// Title of the deny bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Deny {name}?'**
  String approvalDenyTitle(String name);

  /// Body text of the deny bottom sheet
  ///
  /// In en, this message translates to:
  /// **'The agent won\'t get access to this entry.'**
  String get approvalDenyText;

  /// Deny button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Denying…'**
  String get approvalDenying;

  /// Title of the re-grant (grant again) bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Grant again'**
  String get approvalRegrantTitle;

  /// Re-grant button label
  ///
  /// In en, this message translates to:
  /// **'Grant again'**
  String get approvalRegrant;

  /// Re-grant button label while submitting
  ///
  /// In en, this message translates to:
  /// **'Granting…'**
  String get approvalRegranting;

  /// Error — 404 on approval
  ///
  /// In en, this message translates to:
  /// **'This request no longer exists.'**
  String get approvalErrorNotFound;

  /// Error — 403 on approval
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage grants.'**
  String get approvalErrorForbidden;

  /// Error — 400/409 on approval
  ///
  /// In en, this message translates to:
  /// **'The request was rejected. Please check and try again.'**
  String get approvalErrorValidation;

  /// Error — network failure on approval
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get approvalErrorNetwork;

  /// Error — on-device crypto failure producing the envelope
  ///
  /// In en, this message translates to:
  /// **'Could not securely prepare the credential. Please try again.'**
  String get approvalErrorCrypto;

  /// Error — vault locked, no in-memory key to produce the envelope
  ///
  /// In en, this message translates to:
  /// **'Unlock your vault first to approve this request.'**
  String get approvalErrorVaultLocked;

  /// Error — unexpected failure on approval
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get approvalErrorUnknown;

  /// No description provided for @grantAccessTitleAgent.
  ///
  /// In en, this message translates to:
  /// **'Add agent'**
  String get grantAccessTitleAgent;

  /// No description provided for @grantAccessTitleVault.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get grantAccessTitleVault;

  /// No description provided for @grantAccessPickAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get grantAccessPickAgent;

  /// No description provided for @grantAccessPickVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get grantAccessPickVault;

  /// No description provided for @grantAccessNoAgents.
  ///
  /// In en, this message translates to:
  /// **'No active agents to grant'**
  String get grantAccessNoAgents;

  /// No description provided for @grantAccessNoVaults.
  ///
  /// In en, this message translates to:
  /// **'No vaults available'**
  String get grantAccessNoVaults;

  /// No description provided for @grantAccessSelectAgent.
  ///
  /// In en, this message translates to:
  /// **'Select an agent'**
  String get grantAccessSelectAgent;

  /// No description provided for @grantAccessSelectVault.
  ///
  /// In en, this message translates to:
  /// **'Select a vault'**
  String get grantAccessSelectVault;

  /// No description provided for @grantAccessConfirm.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get grantAccessConfirm;

  /// No description provided for @grantAccessGranting.
  ///
  /// In en, this message translates to:
  /// **'Granting…'**
  String get grantAccessGranting;

  /// No description provided for @grantAccessError.
  ///
  /// In en, this message translates to:
  /// **'Could not create the grant. Please try again.'**
  String get grantAccessError;

  /// Warning-zone title shown before creating a FULL vault grant
  ///
  /// In en, this message translates to:
  /// **'FULL VAULT TRUST'**
  String get grantAccessFullTrustTitle;

  /// Security warning explaining the cryptographic trust and revocation limit of a FULL grant
  ///
  /// In en, this message translates to:
  /// **'This grants cryptographic access to every current and future entry in this vault. Revoking blocks new online delivery but cannot erase a key copied by a compromised agent; rotate the Vault Key after suspected compromise.'**
  String get grantAccessFullTrustBody;

  /// No description provided for @grantAddGrant.
  ///
  /// In en, this message translates to:
  /// **'Add grant'**
  String get grantAddGrant;

  /// No description provided for @approvalMethodGetDesc.
  ///
  /// In en, this message translates to:
  /// **'Returns the secret as plaintext to the agent.'**
  String get approvalMethodGetDesc;

  /// No description provided for @approvalMethodExecDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs a command with the secret in its environment — never enters the agent\'s context.'**
  String get approvalMethodExecDesc;

  /// No description provided for @approvalMethodInjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Fills a login form in the agent\'s browser — never enters the agent\'s context.'**
  String get approvalMethodInjectDesc;

  /// No description provided for @approvalMethodsSelect.
  ///
  /// In en, this message translates to:
  /// **'Select methods'**
  String get approvalMethodsSelect;

  /// No description provided for @approvalMethodsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get approvalMethodsDone;

  /// No description provided for @approvalMethodRequested.
  ///
  /// In en, this message translates to:
  /// **'requested'**
  String get approvalMethodRequested;

  /// No description provided for @inboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inboxTitle;

  /// No description provided for @inboxSegAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inboxSegAll;

  /// No description provided for @inboxTodo.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get inboxTodo;

  /// No description provided for @inboxHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get inboxHistory;

  /// No description provided for @inboxSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by agent, entry or vault…'**
  String get inboxSearchHint;

  /// No description provided for @inboxMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get inboxMarkAllRead;

  /// No description provided for @inboxMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get inboxMoreActions;

  /// No description provided for @inboxGrantsMenu.
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get inboxGrantsMenu;

  /// No description provided for @inboxPreferencesMenu.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get inboxPreferencesMenu;

  /// No description provided for @inboxAcceptAction.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get inboxAcceptAction;

  /// No description provided for @inboxViewAgent.
  ///
  /// In en, this message translates to:
  /// **'View Agent'**
  String get inboxViewAgent;

  /// No description provided for @inboxViewAccess.
  ///
  /// In en, this message translates to:
  /// **'View Access'**
  String get inboxViewAccess;

  /// No description provided for @inboxViewEntry.
  ///
  /// In en, this message translates to:
  /// **'View Entry'**
  String get inboxViewEntry;

  /// No description provided for @inboxGrantsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No grants yet'**
  String get inboxGrantsEmpty;

  /// No description provided for @inboxGrantsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access you grant to your agents will appear here.'**
  String get inboxGrantsEmptyHint;

  /// No description provided for @inboxActionGone.
  ///
  /// In en, this message translates to:
  /// **'This action is no longer available.'**
  String get inboxActionGone;

  /// No description provided for @inboxAllEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your inbox is empty'**
  String get inboxAllEmpty;

  /// No description provided for @inboxAllEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Requests, approvals and other agent activity will appear here.'**
  String get inboxAllEmptyHint;

  /// No description provided for @inboxTodoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention'**
  String get inboxTodoEmpty;

  /// No description provided for @inboxTodoEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access requests and other actions from your agents will show up here.'**
  String get inboxTodoEmptyHint;

  /// No description provided for @inboxUpdatesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get inboxUpdatesEmpty;

  /// No description provided for @inboxUpdatesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Approved, revoked and other resolved items will appear here.'**
  String get inboxUpdatesEmptyHint;

  /// No description provided for @inboxErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to view notifications.'**
  String get inboxErrorForbidden;

  /// No description provided for @inboxErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get inboxErrorNetwork;

  /// No description provided for @inboxErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications. Please try again.'**
  String get inboxErrorUnknown;

  /// Fallback for a notification agent name
  ///
  /// In en, this message translates to:
  /// **'An agent'**
  String get notifUnnamedAgent;

  /// Placeholder on agent cards when the agent has no name yet
  ///
  /// In en, this message translates to:
  /// **'Unknown agent'**
  String get notifUnknownAgent;

  /// No description provided for @notifTitleGrantPending.
  ///
  /// In en, this message translates to:
  /// **'Access request'**
  String get notifTitleGrantPending;

  /// No description provided for @notifTitleAgentPending.
  ///
  /// In en, this message translates to:
  /// **'New agent'**
  String get notifTitleAgentPending;

  /// No description provided for @notifTitleAgentApproved.
  ///
  /// In en, this message translates to:
  /// **'Agent approved'**
  String get notifTitleAgentApproved;

  /// No description provided for @notifTitleGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get notifTitleGrantRevoked;

  /// No description provided for @notifTitleGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get notifTitleGrantApproved;

  /// No description provided for @notifTitleGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get notifTitleGrantDenied;

  /// No description provided for @notifTitleCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'Credential not working'**
  String get notifTitleCredentialStale;

  /// No description provided for @notifSubGrantPending.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubGrantPending(String agent);

  /// No description provided for @notifSubAgentPending.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubAgentPending(String agent);

  /// No description provided for @notifSubAgentApproved.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubAgentApproved(String agent);

  /// No description provided for @notifSubCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'reported by {agent}'**
  String notifSubCredentialStale(String agent);

  /// No description provided for @notifSubGrantUpdate.
  ///
  /// In en, this message translates to:
  /// **'{agent}'**
  String notifSubGrantUpdate(String agent);

  /// No description provided for @notifRowEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get notifRowEntry;

  /// No description provided for @notifRowMethods.
  ///
  /// In en, this message translates to:
  /// **'Methods'**
  String get notifRowMethods;

  /// No description provided for @notifRowReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get notifRowReason;

  /// No description provided for @notifRowHostIp.
  ///
  /// In en, this message translates to:
  /// **'Host · Ip'**
  String get notifRowHostIp;

  /// No description provided for @notifRowError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get notifRowError;

  /// No description provided for @notifRowAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get notifRowAttempts;

  /// No description provided for @notifRowNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get notifRowNote;

  /// No description provided for @notifRowAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get notifRowAccess;

  /// No description provided for @notifRowBy.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get notifRowBy;

  /// No description provided for @notifRowAgentId.
  ///
  /// In en, this message translates to:
  /// **'Agent Id'**
  String get notifRowAgentId;

  /// No description provided for @notifRowPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get notifRowPublicKey;

  /// No description provided for @notifRowType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get notifRowType;

  /// No description provided for @notifAccessUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get notifAccessUnlimited;

  /// No description provided for @notifPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get notifPlaceholder;

  /// No description provided for @notifFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter by type'**
  String get notifFilterTitle;

  /// No description provided for @notifFilterClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notifFilterClear;

  /// No description provided for @notifPrefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notifPrefsTitle;

  /// No description provided for @notifPrefsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to be notified for each type. Some critical types stay on in your inbox.'**
  String get notifPrefsHint;

  /// No description provided for @notifPrefsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No preferences available.'**
  String get notifPrefsEmpty;

  /// No description provided for @notifPrefsSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your preference. Please try again.'**
  String get notifPrefsSaveError;

  /// No description provided for @notifPrefsMandatory.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get notifPrefsMandatory;

  /// No description provided for @notifPrefsChannelInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get notifPrefsChannelInbox;

  /// No description provided for @notifPrefsChannelRealtime.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get notifPrefsChannelRealtime;

  /// No description provided for @notifPrefsChannelPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get notifPrefsChannelPush;

  /// No description provided for @notifPrefsTypeAgentPending.
  ///
  /// In en, this message translates to:
  /// **'New agent to accept'**
  String get notifPrefsTypeAgentPending;

  /// No description provided for @notifPrefsTypeGrantPending.
  ///
  /// In en, this message translates to:
  /// **'Access requests'**
  String get notifPrefsTypeGrantPending;

  /// No description provided for @notifPrefsTypeGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get notifPrefsTypeGrantRevoked;

  /// No description provided for @notifPrefsTypeGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get notifPrefsTypeGrantApproved;

  /// No description provided for @notifPrefsTypeGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get notifPrefsTypeGrantDenied;

  /// No description provided for @notifPrefsTypeCredentialStale.
  ///
  /// In en, this message translates to:
  /// **'Credential stale'**
  String get notifPrefsTypeCredentialStale;

  /// No description provided for @auditSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search audit log…'**
  String get auditSearchHint;

  /// No description provided for @auditLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get auditLoadMore;

  /// No description provided for @auditLoadMoreError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more logs.'**
  String get auditLoadMoreError;

  /// No description provided for @auditEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get auditEmptyTitle;

  /// No description provided for @auditEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Access and grant events for this entry will appear here.'**
  String get auditEmptyHint;

  /// No description provided for @auditEmptyFilteredTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching events'**
  String get auditEmptyFilteredTitle;

  /// No description provided for @auditEmptyFilteredHint.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters or search.'**
  String get auditEmptyFilteredHint;

  /// No description provided for @auditFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter logs'**
  String get auditFilterTitle;

  /// No description provided for @auditFilterEventTypes.
  ///
  /// In en, this message translates to:
  /// **'Event types'**
  String get auditFilterEventTypes;

  /// No description provided for @auditFilterAllEventTypes.
  ///
  /// In en, this message translates to:
  /// **'All event types'**
  String get auditFilterAllEventTypes;

  /// No description provided for @auditFilterAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get auditFilterAgent;

  /// No description provided for @auditFilterAllAgents.
  ///
  /// In en, this message translates to:
  /// **'All agents'**
  String get auditFilterAllAgents;

  /// No description provided for @multiSelectNSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String multiSelectNSelected(int count);

  /// No description provided for @multiSelectSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get multiSelectSearchHint;

  /// No description provided for @multiSelectNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get multiSelectNoResults;

  /// No description provided for @auditFilterDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get auditFilterDateRange;

  /// No description provided for @auditFilterFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get auditFilterFrom;

  /// No description provided for @auditFilterTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get auditFilterTo;

  /// No description provided for @auditFilterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get auditFilterReset;

  /// No description provided for @auditFilterApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get auditFilterApply;

  /// No description provided for @auditDetailEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get auditDetailEntry;

  /// No description provided for @auditDetailVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get auditDetailVault;

  /// No description provided for @auditDetailReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get auditDetailReason;

  /// No description provided for @auditDetailNone.
  ///
  /// In en, this message translates to:
  /// **'No additional details.'**
  String get auditDetailNone;

  /// No description provided for @auditActorOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get auditActorOwner;

  /// No description provided for @auditActorSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get auditActorSystem;

  /// No description provided for @auditActorAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get auditActorAgent;

  /// No description provided for @auditErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to view audit logs.'**
  String get auditErrorForbidden;

  /// No description provided for @auditErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Audit logs are unavailable for this vault.'**
  String get auditErrorNotFound;

  /// No description provided for @auditErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get auditErrorNetwork;

  /// No description provided for @auditErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the audit log. Please try again.'**
  String get auditErrorGeneric;

  /// No description provided for @auditEventGrantCreated.
  ///
  /// In en, this message translates to:
  /// **'Access granted'**
  String get auditEventGrantCreated;

  /// No description provided for @auditEventGrantRequested.
  ///
  /// In en, this message translates to:
  /// **'Access requested'**
  String get auditEventGrantRequested;

  /// No description provided for @auditEventGrantApproved.
  ///
  /// In en, this message translates to:
  /// **'Access approved'**
  String get auditEventGrantApproved;

  /// No description provided for @auditEventGrantDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get auditEventGrantDenied;

  /// No description provided for @auditEventGrantRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get auditEventGrantRevoked;

  /// No description provided for @auditEventGrantConsumed.
  ///
  /// In en, this message translates to:
  /// **'Grant consumed'**
  String get auditEventGrantConsumed;

  /// No description provided for @auditEventGrantExpired.
  ///
  /// In en, this message translates to:
  /// **'Grant expired'**
  String get auditEventGrantExpired;

  /// No description provided for @auditEventGrantSuperseded.
  ///
  /// In en, this message translates to:
  /// **'Grant superseded'**
  String get auditEventGrantSuperseded;

  /// No description provided for @auditEventCredentialAccessed.
  ///
  /// In en, this message translates to:
  /// **'Credential accessed'**
  String get auditEventCredentialAccessed;

  /// No description provided for @auditEventCredentialAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get auditEventCredentialAccessDenied;

  /// No description provided for @auditEventAgentEnrolled.
  ///
  /// In en, this message translates to:
  /// **'Agent enrolled'**
  String get auditEventAgentEnrolled;

  /// No description provided for @auditEventAgentBlocked.
  ///
  /// In en, this message translates to:
  /// **'Agent blocked'**
  String get auditEventAgentBlocked;

  /// No description provided for @auditEventAgentReactivated.
  ///
  /// In en, this message translates to:
  /// **'Agent reactivated'**
  String get auditEventAgentReactivated;

  /// No description provided for @auditEventAgentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Agent deleted'**
  String get auditEventAgentDeleted;

  /// No description provided for @auditEventVaultCreated.
  ///
  /// In en, this message translates to:
  /// **'Vault created'**
  String get auditEventVaultCreated;

  /// No description provided for @auditEventVaultUpdated.
  ///
  /// In en, this message translates to:
  /// **'Vault updated'**
  String get auditEventVaultUpdated;

  /// No description provided for @auditEventVaultDeleted.
  ///
  /// In en, this message translates to:
  /// **'Vault deleted'**
  String get auditEventVaultDeleted;

  /// Audit event label — vault entries exported to a file
  ///
  /// In en, this message translates to:
  /// **'Vault exported'**
  String get auditEventVaultExported;

  /// No description provided for @auditEventEntryCreated.
  ///
  /// In en, this message translates to:
  /// **'Entry created'**
  String get auditEventEntryCreated;

  /// No description provided for @auditEventEntryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get auditEventEntryUpdated;

  /// No description provided for @auditEventEntryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get auditEventEntryDeleted;

  /// No description provided for @auditEventApiKeyCreated.
  ///
  /// In en, this message translates to:
  /// **'API key created'**
  String get auditEventApiKeyCreated;

  /// No description provided for @auditEventApiKeyActivated.
  ///
  /// In en, this message translates to:
  /// **'API key activated'**
  String get auditEventApiKeyActivated;

  /// No description provided for @auditEventApiKeyRevoked.
  ///
  /// In en, this message translates to:
  /// **'API key revoked'**
  String get auditEventApiKeyRevoked;

  /// No description provided for @auditEventApiKeyDeleted.
  ///
  /// In en, this message translates to:
  /// **'API key deleted'**
  String get auditEventApiKeyDeleted;

  /// No description provided for @auditEventOrgCreated.
  ///
  /// In en, this message translates to:
  /// **'Organization created'**
  String get auditEventOrgCreated;

  /// No description provided for @auditEventOrgUpdated.
  ///
  /// In en, this message translates to:
  /// **'Organization updated'**
  String get auditEventOrgUpdated;

  /// No description provided for @auditEventUserSignedUp.
  ///
  /// In en, this message translates to:
  /// **'User signed up'**
  String get auditEventUserSignedUp;

  /// No description provided for @auditEventAccountSetupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account setup completed'**
  String get auditEventAccountSetupCompleted;

  /// No description provided for @auditEventAccountRecoveryCompleted.
  ///
  /// In en, this message translates to:
  /// **'Account recovery completed'**
  String get auditEventAccountRecoveryCompleted;

  /// No description provided for @auditEventLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get auditEventLoginFailed;

  /// No description provided for @auditEventUnknown.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get auditEventUnknown;

  /// Title of the org-wide audit Logs screen
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get auditScreenTitle;

  /// No description provided for @auditFilterVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get auditFilterVault;

  /// No description provided for @auditFilterAllVaults.
  ///
  /// In en, this message translates to:
  /// **'All vaults'**
  String get auditFilterAllVaults;

  /// No description provided for @auditFilterUser.
  ///
  /// In en, this message translates to:
  /// **'Performed by'**
  String get auditFilterUser;

  /// No description provided for @auditFilterAllUsers.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get auditFilterAllUsers;

  /// No description provided for @auditUserUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown user'**
  String get auditUserUnknown;

  /// No description provided for @auditUserUnknownShort.
  ///
  /// In en, this message translates to:
  /// **'Unknown user ({id})'**
  String auditUserUnknownShort(String id);

  /// No description provided for @auditGroupCredentialAccess.
  ///
  /// In en, this message translates to:
  /// **'Accessed'**
  String get auditGroupCredentialAccess;

  /// No description provided for @auditGroupGrants.
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get auditGroupGrants;

  /// No description provided for @auditGroupVaultEntry.
  ///
  /// In en, this message translates to:
  /// **'Vault & entries'**
  String get auditGroupVaultEntry;

  /// No description provided for @auditGroupAgentLifecycle.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get auditGroupAgentLifecycle;

  /// No description provided for @auditGroupApiKeys.
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get auditGroupApiKeys;

  /// No description provided for @auditGroupOrgAccount.
  ///
  /// In en, this message translates to:
  /// **'Org & account'**
  String get auditGroupOrgAccount;

  /// No description provided for @auditLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'Event legend'**
  String get auditLegendTitle;

  /// No description provided for @auditLegendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What the colours on each log entry mean.'**
  String get auditLegendSubtitle;

  /// No description provided for @auditSentenceCreated.
  ///
  /// In en, this message translates to:
  /// **'{actor} created {object}'**
  String auditSentenceCreated(String actor, String object);

  /// No description provided for @auditSentenceUpdated.
  ///
  /// In en, this message translates to:
  /// **'{actor} updated {object}'**
  String auditSentenceUpdated(String actor, String object);

  /// No description provided for @auditSentenceDeleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} deleted {object}'**
  String auditSentenceDeleted(String actor, String object);

  /// Audit sentence — vault exported
  ///
  /// In en, this message translates to:
  /// **'{actor} exported {object}'**
  String auditSentenceExported(String actor, String object);

  /// No description provided for @auditSentenceActivated.
  ///
  /// In en, this message translates to:
  /// **'{actor} activated {object}'**
  String auditSentenceActivated(String actor, String object);

  /// No description provided for @auditSentenceRevoked.
  ///
  /// In en, this message translates to:
  /// **'{actor} revoked {object}'**
  String auditSentenceRevoked(String actor, String object);

  /// No description provided for @auditSentenceBlocked.
  ///
  /// In en, this message translates to:
  /// **'{actor} blocked {object}'**
  String auditSentenceBlocked(String actor, String object);

  /// No description provided for @auditSentenceReactivated.
  ///
  /// In en, this message translates to:
  /// **'{actor} reactivated {object}'**
  String auditSentenceReactivated(String actor, String object);

  /// No description provided for @auditSentenceUserSignedUp.
  ///
  /// In en, this message translates to:
  /// **'{actor} signed up'**
  String auditSentenceUserSignedUp(String actor);

  /// No description provided for @auditSentenceAccountSetupCompleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} completed account setup'**
  String auditSentenceAccountSetupCompleted(String actor);

  /// No description provided for @auditSentenceAccountRecoveryCompleted.
  ///
  /// In en, this message translates to:
  /// **'{actor} completed account recovery'**
  String auditSentenceAccountRecoveryCompleted(String actor);

  /// No description provided for @auditSentenceLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed login attempt'**
  String get auditSentenceLoginFailed;

  /// No description provided for @auditSentenceAgentEnrolled.
  ///
  /// In en, this message translates to:
  /// **'{agent} enrolled in the system'**
  String auditSentenceAgentEnrolled(String agent);

  /// No description provided for @auditObjectVaultNamed.
  ///
  /// In en, this message translates to:
  /// **'vault {name}'**
  String auditObjectVaultNamed(String name);

  /// No description provided for @auditObjectEntryNamed.
  ///
  /// In en, this message translates to:
  /// **'entry {name}'**
  String auditObjectEntryNamed(String name);

  /// No description provided for @auditObjectOrgNamed.
  ///
  /// In en, this message translates to:
  /// **'organization {name}'**
  String auditObjectOrgNamed(String name);

  /// No description provided for @auditObjectApiKeyNamed.
  ///
  /// In en, this message translates to:
  /// **'API key {name}'**
  String auditObjectApiKeyNamed(String name);

  /// No description provided for @auditObjectAgentNamed.
  ///
  /// In en, this message translates to:
  /// **'agent {name}'**
  String auditObjectAgentNamed(String name);

  /// No description provided for @auditObjectVault.
  ///
  /// In en, this message translates to:
  /// **'a vault'**
  String get auditObjectVault;

  /// No description provided for @auditObjectEntry.
  ///
  /// In en, this message translates to:
  /// **'an entry'**
  String get auditObjectEntry;

  /// No description provided for @auditObjectOrg.
  ///
  /// In en, this message translates to:
  /// **'the organization'**
  String get auditObjectOrg;

  /// No description provided for @auditObjectApiKey.
  ///
  /// In en, this message translates to:
  /// **'an API key'**
  String get auditObjectApiKey;

  /// No description provided for @auditObjectAgent.
  ///
  /// In en, this message translates to:
  /// **'an agent'**
  String get auditObjectAgent;

  /// Greeting on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboardGoodMorning;

  /// Search placeholder on dashboard
  ///
  /// In en, this message translates to:
  /// **'Agents, vaults, entries…'**
  String get dashboardSearchHint;

  /// Localized name for the default vault auto-created during onboarding
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get defaultVaultName;

  /// Title of the onboarding progress card
  ///
  /// In en, this message translates to:
  /// **'Set up Palladin'**
  String get dashboardOnboardingTitle;

  /// Subtitle of the onboarding progress card
  ///
  /// In en, this message translates to:
  /// **'Complete these steps to start managing access securely'**
  String get dashboardOnboardingSubtitle;

  /// Progress counter in the onboarding card
  ///
  /// In en, this message translates to:
  /// **'{completed} of 4 completed'**
  String dashboardOnboardingProgress(int completed);

  /// Link to dismiss the onboarding checklist
  ///
  /// In en, this message translates to:
  /// **'Skip setup'**
  String get dashboardOnboardingSkipSetup;

  /// Step 1 title
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get dashboardOnboardingStep1Title;

  /// Step 1 description
  ///
  /// In en, this message translates to:
  /// **'Respond in seconds — agents wait for your approval. Faster responses mean smoother AI workflows.'**
  String get dashboardOnboardingStep1Description;

  /// Enable notifications button
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get dashboardOnboardingStep1Enable;

  /// Skip notifications step button
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get dashboardOnboardingStep1Skip;

  /// Button shown instead of Enable when the OS notification permission was denied — opens system app settings
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get dashboardOnboardingStep1OpenSettings;

  /// Step 2 title — prompts user to add a password entry or import
  ///
  /// In en, this message translates to:
  /// **'Add your first entry or import passwords'**
  String get dashboardOnboardingStep2Title;

  /// Step 2 description
  ///
  /// In en, this message translates to:
  /// **'Your Personal vault is ready — add a password entry manually or import your existing credentials.'**
  String get dashboardOnboardingStep2Description;

  /// Step 2 CTA button — navigates to vault list so user can add first entry
  ///
  /// In en, this message translates to:
  /// **'Go to Vaults'**
  String get dashboardOnboardingStep2Cta;

  /// Step 3 title
  ///
  /// In en, this message translates to:
  /// **'Add an API Key'**
  String get dashboardOnboardingStep3Title;

  /// Step 3 description
  ///
  /// In en, this message translates to:
  /// **'Connect Palladin to external services'**
  String get dashboardOnboardingStep3Description;

  /// Step 3 CTA button
  ///
  /// In en, this message translates to:
  /// **'Add API Key'**
  String get dashboardOnboardingStep3Cta;

  /// Step 4 title
  ///
  /// In en, this message translates to:
  /// **'Register an Agent'**
  String get dashboardOnboardingStep4Title;

  /// Step 4 description
  ///
  /// In en, this message translates to:
  /// **'Add your first AI agent that can request access'**
  String get dashboardOnboardingStep4Description;

  /// Step 4 CTA button
  ///
  /// In en, this message translates to:
  /// **'Register Agent'**
  String get dashboardOnboardingStep4Cta;

  /// Step number badge
  ///
  /// In en, this message translates to:
  /// **'Step {n}'**
  String dashboardOnboardingStep(int n);

  /// Warning label on the unknown agent card
  ///
  /// In en, this message translates to:
  /// **'Unregistered agent'**
  String get dashboardUnknownAgentWarning;

  /// Unknown agent card description
  ///
  /// In en, this message translates to:
  /// **'This agent is not yet in the system. You can register it and approve access at the same time.'**
  String get dashboardUnknownAgentDescription;

  /// Register & Approve button label
  ///
  /// In en, this message translates to:
  /// **'Register & Approve'**
  String get dashboardUnknownAgentRegisterAndApprove;

  /// Reject button label on unknown agent card
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get dashboardUnknownAgentReject;

  /// Snackbar confirmation shown after the owner rejects an unknown-agent access request
  ///
  /// In en, this message translates to:
  /// **'Request rejected'**
  String get dashboardRequestRejected;

  /// Pending approvals section header
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get dashboardPendingApprovals;

  /// Recent activity section header
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get dashboardRecentActivity;

  /// Empty state message for activity section
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get dashboardNoActivity;

  /// Section header for recently added or updated entries on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Recently added / modified'**
  String get dashboardRecentlyModified;

  /// See all link in section headers
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get dashboardSeeAll;

  /// Header for the focus-driven recent-entries suggestions shown under the dashboard search field
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get dashboardSearchRecent;

  /// Empty state shown in search results
  ///
  /// In en, this message translates to:
  /// **'No results for this search'**
  String get searchResultsEmpty;

  /// Error state for search results
  ///
  /// In en, this message translates to:
  /// **'Search failed. Please try again.'**
  String get searchResultsError;

  /// Type badge label for agent search results
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get searchTypeBadgeAgent;

  /// No description provided for @searchTypeBadgeMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get searchTypeBadgeMember;

  /// Type badge label for vault search results
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get searchTypeBadgeVault;

  /// Type badge label for entry search results
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get searchTypeBadgeEntry;

  /// Title of the import wizard
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importTitle;

  /// Button to pick the export file to import
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get importChooseFile;

  /// Heading on the import wizard intro step
  ///
  /// In en, this message translates to:
  /// **'Import from another password manager'**
  String get importIntroTitle;

  /// Body copy on the import wizard intro step
  ///
  /// In en, this message translates to:
  /// **'Pick an export file from Chrome, Bitwarden, 1Password, LastPass, and more. Everything is parsed and encrypted on your device.'**
  String get importIntroBody;

  /// Hint listing the supported import file types
  ///
  /// In en, this message translates to:
  /// **'Supported: CSV, JSON, XML, and ZIP (.1pux) exports'**
  String get importSupportedFormats;

  /// Progress label while parsing the picked file
  ///
  /// In en, this message translates to:
  /// **'Reading file…'**
  String get importParsing;

  /// Subtitle on the import vault picker
  ///
  /// In en, this message translates to:
  /// **'Choose where the imported entries go'**
  String get importSelectVaultSubtitle;

  /// Empty state when there are no vaults to import into
  ///
  /// In en, this message translates to:
  /// **'No vaults yet. Create a vault first, then import into it.'**
  String get importNoVaults;

  /// Count of parsed entries
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String importEntriesCount(int count);

  /// Count of skipped non-login items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 non-login item skipped} other{{count} non-login items skipped}}'**
  String importSkippedNote(int count);

  /// Label above the conflict-resolution selector
  ///
  /// In en, this message translates to:
  /// **'For entries that already exist'**
  String get importConflictStrategyLabel;

  /// Conflict strategy — skip the imported entry
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get importStrategySkip;

  /// Conflict strategy — overwrite the existing entry
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get importStrategyOverwrite;

  /// Conflict strategy — import under a renamed label
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get importStrategyRename;

  /// Badge on a preview row that collides with an existing entry
  ///
  /// In en, this message translates to:
  /// **'Exists'**
  String get importConflictBadge;

  /// Badge indicating the entry carries a TOTP secret
  ///
  /// In en, this message translates to:
  /// **'2FA'**
  String get importTotpBadge;

  /// Badge indicating the entry has notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get importNotesBadge;

  /// Commit button on the import preview
  ///
  /// In en, this message translates to:
  /// **'Import {count, plural, =1{1 entry} other{{count} entries}}'**
  String importAction(int count);

  /// Progress label during import commit
  ///
  /// In en, this message translates to:
  /// **'Importing… {done} of {total}'**
  String importImporting(int done, int total);

  /// Progress label while imported website icons become ready
  ///
  /// In en, this message translates to:
  /// **'Preparing icons… {done} of {total} (up to 15 seconds)'**
  String importPreparingIcons(int done, int total);

  /// Heading on the import success step
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importSuccessTitle;

  /// Import success summary
  ///
  /// In en, this message translates to:
  /// **'{created, plural, =1{1 added} other{{created} added}}, {updated, plural, =1{1 updated} other{{updated} updated}}'**
  String importSuccessBody(int created, int updated);

  /// Skipped count on the import success step
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String importSuccessSkipped(int count);

  /// Button to close the import wizard after success
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get importDone;

  /// Heading on the import failure step
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailedTitle;

  /// Button to retry import with a different file
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get importTryAnother;

  /// Import error — empty file
  ///
  /// In en, this message translates to:
  /// **'That file is empty.'**
  String get importErrorEmpty;

  /// Import error — encrypted file
  ///
  /// In en, this message translates to:
  /// **'This export is encrypted and can\'t be read. Export an unencrypted file (e.g. KeePass XML) and try again.'**
  String get importErrorEncrypted;

  /// Import error — unrecognised format
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t recognise this file. Try a CSV, JSON, or XML export.'**
  String get importErrorUnrecognised;

  /// Import error — no login entries
  ///
  /// In en, this message translates to:
  /// **'No login entries were found in this file.'**
  String get importErrorNoEntries;

  /// Import error — crypto failure
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t encrypt the entries. Lock and unlock your vault, then try again.'**
  String get importErrorCrypto;

  /// Import error — network failure
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get importErrorNetwork;

  /// Import error — unknown
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get importErrorUnknown;

  /// Title on the manual column mapping step
  ///
  /// In en, this message translates to:
  /// **'Map columns'**
  String get importColumnMapTitle;

  /// Subtitle on the manual column mapping step
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t detect this format. Tell us which column is which.'**
  String get importColumnMapSubtitle;

  /// Column mapper — name field
  ///
  /// In en, this message translates to:
  /// **'Name column'**
  String get importColumnName;

  /// Column mapper — username field
  ///
  /// In en, this message translates to:
  /// **'Username column'**
  String get importColumnUsername;

  /// Column mapper — password field (required)
  ///
  /// In en, this message translates to:
  /// **'Password column'**
  String get importColumnPassword;

  /// Column mapper — URL field
  ///
  /// In en, this message translates to:
  /// **'URL column'**
  String get importColumnUrl;

  /// Column mapper — notes field
  ///
  /// In en, this message translates to:
  /// **'Notes column'**
  String get importColumnNotes;

  /// Column mapper — TOTP field
  ///
  /// In en, this message translates to:
  /// **'TOTP column'**
  String get importColumnTotp;

  /// Column mapper — unmapped option
  ///
  /// In en, this message translates to:
  /// **'— None —'**
  String get importColumnNone;

  /// Column mapper — label for a CSV column with a blank header
  ///
  /// In en, this message translates to:
  /// **'Column {number}'**
  String importColumnFallback(int number);

  /// Fallback name for an imported entry whose source carried no title
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get importUntitledFallback;

  /// Button to proceed from column mapping
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get importColumnMapContinue;

  /// Validation when no password column is mapped
  ///
  /// In en, this message translates to:
  /// **'Choose at least a password column.'**
  String get importColumnMapNeedPassword;

  /// Format badge label for a generic CSV
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get importFormatGeneric;

  /// Format badge label for a manually-mapped CSV
  ///
  /// In en, this message translates to:
  /// **'Custom CSV'**
  String get importFormatManual;

  /// Settings drawer item that opens the import flow
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsImport;

  /// Vault detail menu action to import entries
  ///
  /// In en, this message translates to:
  /// **'Import entries'**
  String get vaultActionImport;

  /// Vault detail menu action to export the vault
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get vaultActionExport;

  /// Title of the export sheet
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get exportTitle;

  /// Export format option — CSV
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportFormatCsv;

  /// Export format option — JSON
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportFormatJson;

  /// Hint under the CSV export option
  ///
  /// In en, this message translates to:
  /// **'Compatible with Chrome, Bitwarden, and most managers.'**
  String get exportCsvHint;

  /// Hint under the JSON export option
  ///
  /// In en, this message translates to:
  /// **'Full Palladin format — re-imports losslessly.'**
  String get exportJsonHint;

  /// Title of the plaintext-secrets export warning
  ///
  /// In en, this message translates to:
  /// **'PLAINTEXT EXPORT'**
  String get exportWarningTitle;

  /// Body of the plaintext-secrets export warning
  ///
  /// In en, this message translates to:
  /// **'The file contains your passwords and TOTP secrets in plaintext. Anyone with the file can read them. Store it securely and delete it when you\'re done.'**
  String get exportWarningBody;

  /// Confirm button on the export sheet
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportConfirm;

  /// Export success snackbar
  ///
  /// In en, this message translates to:
  /// **'Exported {count} entries'**
  String exportSuccess(int count);

  /// Export error — empty vault
  ///
  /// In en, this message translates to:
  /// **'This vault has no entries to export.'**
  String get exportEmpty;

  /// Export error — crypto failure
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t decrypt the vault. Lock and unlock, then try again.'**
  String get exportErrorCrypto;

  /// Export error — network failure
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get exportErrorNetwork;

  /// Export error — unknown
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get exportErrorUnknown;

  /// Export scope toggle for archived entries
  ///
  /// In en, this message translates to:
  /// **'Include archived entries'**
  String get exportIncludeArchived;

  /// Export scope toggle for deleted entries
  ///
  /// In en, this message translates to:
  /// **'Include recently deleted entries'**
  String get exportIncludeDeleted;

  /// Export scope toggle for entry history
  ///
  /// In en, this message translates to:
  /// **'Include previous revisions'**
  String get exportIncludeHistory;

  /// Explains temporary-file deletion and share ownership
  ///
  /// In en, this message translates to:
  /// **'Palladin removes its temporary copy after sharing on a best-effort basis. Copies created by the selected app or cloud service are controlled by that recipient and may remain there.'**
  String get exportDeletionDisclosure;

  /// Export exceeded bounded local limits
  ///
  /// In en, this message translates to:
  /// **'This export exceeds the local safety limit. Export a smaller scope.'**
  String get exportErrorTooLarge;

  /// Subtitle on the email + password sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign in with your email and master password.'**
  String get authLoginSubtitle;

  /// Email field label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// Email field placeholder
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get authEmailHint;

  /// Inline error when the email is malformed
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authEmailInvalid;

  /// Master password field label on sign-in / register
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get authPasswordLabel;

  /// Primary sign-in button
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get authLoginButton;

  /// Generic login failure (unknown email or bad password)
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get authInvalidCredentials;

  /// Login rejected due to rate limiting / lockout
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get authRateLimited;

  /// Prompt before the sign-up link on the login screen
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccountPrompt;

  /// Sign-up link on the login screen
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUpLink;

  /// Primary registration button
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authRegisterButton;

  /// Divider between password sign-in and OAuth providers
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// Registration screen headline
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authRegisterTitle;

  /// Registration screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Your master password encrypts everything on-device. We never see it.'**
  String get authRegisterSubtitle;

  /// Confirm master password field label on register
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get authRegisterConfirmLabel;

  /// Prompt before the sign-in link on register
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authRegisterHaveAccount;

  /// Sign-in link on the register screen
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authRegisterSignIn;

  /// Register failure — email already registered
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get authRegisterEmailTaken;

  /// Shown while the HIBP breach check runs
  ///
  /// In en, this message translates to:
  /// **'Checking your password...'**
  String get authPasswordChecking;

  /// Compact positive password status after a successful breach check
  ///
  /// In en, this message translates to:
  /// **'Secure!'**
  String get authPasswordSecure;

  /// Compact recommendation for a weak registration password
  ///
  /// In en, this message translates to:
  /// **'Use a longer password with mixed characters.'**
  String get authPasswordImprove;

  /// Compact status when the optional breach check is unavailable
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check breaches - use a unique password.'**
  String get authPasswordCheckUnavailable;

  /// HIBP breach warning message
  ///
  /// In en, this message translates to:
  /// **'Found in a data breach - choose another password.'**
  String get authPasswordBreached;

  /// Warning-zone title on the register recovery backup step
  ///
  /// In en, this message translates to:
  /// **'SAVE YOUR RECOVERY KEY'**
  String get authRecoveryWarningTitle;

  /// Verify-email gate body with the user's email
  ///
  /// In en, this message translates to:
  /// **'We sent a verification link to {email}.'**
  String authVerifyGateSubtitle(String email);

  /// Verify-email gate body when the email is unknown
  ///
  /// In en, this message translates to:
  /// **'We sent you a verification link.'**
  String get authVerifyGateSubtitleNoEmail;

  /// Instruction shown below the verification-email delivery message
  ///
  /// In en, this message translates to:
  /// **'Open it to activate your account.'**
  String get authVerifyGateInstruction;

  /// Resend the verification email
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get authVerifyResendButton;

  /// Confirms that the user has opened the email verification link
  ///
  /// In en, this message translates to:
  /// **'I\'ve verified my email'**
  String get authVerifyCheckAgain;

  /// Snackbar shown when verification is still pending
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm it yet. Open the verification link and try again.'**
  String get authVerifyStillPending;

  /// Snackbar shown when verification or default vault provisioning fails
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t finish setting up your account. Try again.'**
  String get authVerifyCheckError;

  /// Snackbar after a successful resend
  ///
  /// In en, this message translates to:
  /// **'Verification email sent.'**
  String get authVerifyResendSent;

  /// Snackbar after a failed resend
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t resend. Please try again.'**
  String get authVerifyResendError;

  /// Sign out from the verify-email gate
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authVerifyLogout;

  /// Shown while an email-verification token is processed
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get authVerifyingTitle;

  /// Verification success headline
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get authVerifiedTitle;

  /// Verification success body
  ///
  /// In en, this message translates to:
  /// **'Your account is now active.'**
  String get authVerifiedSubtitle;

  /// Continue after a successful verification
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get authVerifyContinue;

  /// Go to login after verification when not signed in
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get authVerifyGoToLogin;

  /// Expired verification link headline
  ///
  /// In en, this message translates to:
  /// **'Link expired'**
  String get authVerifyExpiredTitle;

  /// Expired verification link body
  ///
  /// In en, this message translates to:
  /// **'This verification link has expired. Request a new one.'**
  String get authVerifyExpiredSubtitle;

  /// Invalid verification link headline
  ///
  /// In en, this message translates to:
  /// **'Invalid link'**
  String get authVerifyInvalidTitle;

  /// Invalid verification link body
  ///
  /// In en, this message translates to:
  /// **'This verification link is invalid or has already been used.'**
  String get authVerifyInvalidSubtitle;

  /// TOTP login challenge headline
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get authTotpChallengeTitle;

  /// TOTP login challenge subtitle
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app.'**
  String get authTotpChallengeSubtitle;

  /// Subtitle when using a recovery code at login
  ///
  /// In en, this message translates to:
  /// **'Enter one of your recovery codes.'**
  String get authTotpRecoverySubtitle;

  /// TOTP code field label
  ///
  /// In en, this message translates to:
  /// **'Authentication code'**
  String get authTotpCodeLabel;

  /// Recovery code field label
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get authTotpRecoveryLabel;

  /// Verify the TOTP / recovery code
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authTotpVerifyButton;

  /// Switch to recovery-code entry
  ///
  /// In en, this message translates to:
  /// **'Use a recovery code instead'**
  String get authTotpUseRecovery;

  /// Switch back to authenticator-code entry
  ///
  /// In en, this message translates to:
  /// **'Use an authenticator code instead'**
  String get authTotpUseCode;

  /// Rejected TOTP / recovery code
  ///
  /// In en, this message translates to:
  /// **'Invalid code. Please try again.'**
  String get authTotpInvalid;

  /// TOTP enrollment screen title
  ///
  /// In en, this message translates to:
  /// **'Set up two-factor authentication'**
  String get authTotpEnrollTitle;

  /// TOTP enrollment instructions
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with your authenticator app, or enter the setup key manually.'**
  String get authTotpEnrollSubtitle;

  /// Label for the manual TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Setup key'**
  String get authTotpEnrollSecretLabel;

  /// Copy the TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Copy setup key'**
  String get authTotpEnrollCopyKey;

  /// Snackbar after copying the TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Setup key copied.'**
  String get authTotpEnrollKeyCopied;

  /// TOTP confirmation code field label
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get authTotpEnrollCodeLabel;

  /// Enable TOTP after entering a code
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get authTotpEnrollConfirmButton;

  /// Retry loading the TOTP secret
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get authTotpEnrollRetry;

  /// Recovery codes screen headline
  ///
  /// In en, this message translates to:
  /// **'Save your recovery codes'**
  String get authTotpEnrollRecoveryTitle;

  /// Recovery codes screen body
  ///
  /// In en, this message translates to:
  /// **'Store these somewhere safe. Each code can be used once if you lose your authenticator.'**
  String get authTotpEnrollRecoverySubtitle;

  /// Warning-zone title for recovery codes
  ///
  /// In en, this message translates to:
  /// **'SHOWN ONLY ONCE'**
  String get authTotpEnrollRecoveryWarningTitle;

  /// Warning-zone body for recovery codes
  ///
  /// In en, this message translates to:
  /// **'These codes won\'t be shown again. Save them before you continue.'**
  String get authTotpEnrollRecoveryWarning;

  /// Fallback when no recovery codes are returned
  ///
  /// In en, this message translates to:
  /// **'No recovery codes were returned.'**
  String get authTotpEnrollNoCodes;

  /// Copy all recovery codes
  ///
  /// In en, this message translates to:
  /// **'Copy codes'**
  String get authTotpEnrollCopyCodes;

  /// Snackbar after copying recovery codes
  ///
  /// In en, this message translates to:
  /// **'Recovery codes copied.'**
  String get authTotpEnrollCodesCopied;

  /// Finish TOTP enrollment
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get authTotpEnrollDone;

  /// Change-password screen title
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get authChangePwTitle;

  /// Change-password screen subtitle
  ///
  /// In en, this message translates to:
  /// **'This re-encrypts your vault key on-device. Your recovery key stays the same.'**
  String get authChangePwSubtitle;

  /// Current password field label
  ///
  /// In en, this message translates to:
  /// **'Current master password'**
  String get authChangePwCurrentLabel;

  /// New password field label
  ///
  /// In en, this message translates to:
  /// **'New master password'**
  String get authChangePwNewLabel;

  /// Confirm new password field label
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get authChangePwConfirmLabel;

  /// Inline error when the current password is wrong
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect.'**
  String get authChangePwWrongCurrent;

  /// Inline error when the new password equals the current one
  ///
  /// In en, this message translates to:
  /// **'Choose a password different from your current one.'**
  String get authChangePwSameAsCurrent;

  /// Change-password warning-zone title
  ///
  /// In en, this message translates to:
  /// **'BIOMETRIC UNLOCK'**
  String get authChangePwWarningTitle;

  /// Change-password warning-zone body
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to re-enable biometric unlock after changing your password.'**
  String get authChangePwWarning;

  /// Submit the master password change
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get authChangePwButton;

  /// Snackbar after a successful password change
  ///
  /// In en, this message translates to:
  /// **'Master password changed.'**
  String get authChangePwSuccess;

  /// Settings drawer item — change master password
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get settingsChangePassword;

  /// No description provided for @entryStateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get entryStateActive;

  /// No description provided for @entryStateArchived.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get entryStateArchived;

  /// No description provided for @entryStateDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted'**
  String get entryStateDeleted;

  /// No description provided for @entryArchivedRecoverability.
  ///
  /// In en, this message translates to:
  /// **'Archived · can be restored'**
  String get entryArchivedRecoverability;

  /// No description provided for @entryDeletedRecoverability.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted · recoverable during retention'**
  String get entryDeletedRecoverability;

  /// No description provided for @entryCorruptProjection.
  ///
  /// In en, this message translates to:
  /// **'Encrypted metadata could not be verified'**
  String get entryCorruptProjection;

  /// No description provided for @entryArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get entryArchiveTitle;

  /// No description provided for @entryArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Items kept outside your active vault'**
  String get entryArchiveSubtitle;

  /// No description provided for @entryArchiveSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search archived items'**
  String get entryArchiveSearchHint;

  /// No description provided for @entryArchiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived items'**
  String get entryArchiveEmpty;

  /// No description provided for @entryArchiveRestore.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get entryArchiveRestore;

  /// No description provided for @entryArchiveRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get entryArchiveRestoring;

  /// No description provided for @entryArchiveConflict.
  ///
  /// In en, this message translates to:
  /// **'This item changed on another device. Sync and try again.'**
  String get entryArchiveConflict;

  /// No description provided for @entryArchiveAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get entryArchiveAllTypes;

  /// No description provided for @entryArchiveSortAscending.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get entryArchiveSortAscending;

  /// No description provided for @entryArchiveSortDescending.
  ///
  /// In en, this message translates to:
  /// **'Z–A'**
  String get entryArchiveSortDescending;

  /// No description provided for @entryArchiveSortType.
  ///
  /// In en, this message translates to:
  /// **'By type'**
  String get entryArchiveSortType;

  /// No description provided for @entryDeletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get entryDeletedTitle;

  /// No description provided for @entryDeletedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recoverable items awaiting permanent deletion'**
  String get entryDeletedSubtitle;

  /// No description provided for @entryDeletedSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search recently deleted items'**
  String get entryDeletedSearchHint;

  /// No description provided for @entryDeletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recently deleted items'**
  String get entryDeletedEmpty;

  /// No description provided for @entryDeletedRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get entryDeletedRestore;

  /// No description provided for @entryDeletedPurgeAt.
  ///
  /// In en, this message translates to:
  /// **'Permanently deleted after {date}'**
  String entryDeletedPurgeAt(String date);

  /// No description provided for @entryDeletedPurgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get entryDeletedPurgeTitle;

  /// No description provided for @entryDeletedPurgeWarning.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes all encrypted content, keys and history. This cannot be undone.'**
  String get entryDeletedPurgeWarning;

  /// No description provided for @entryDeletedPurgeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get entryDeletedPurgeConfirm;

  /// No description provided for @vaultDiscoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent Discovery'**
  String get vaultDiscoveryTitle;

  /// No description provided for @vaultDiscoveryNoActiveAgents.
  ///
  /// In en, this message translates to:
  /// **'No active organization agents require Discovery provisioning.'**
  String get vaultDiscoveryNoActiveAgents;

  /// No description provided for @vaultDiscoveryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get vaultDiscoveryCurrent;

  /// No description provided for @vaultDiscoveryPending.
  ///
  /// In en, this message translates to:
  /// **'Pending / stale'**
  String get vaultDiscoveryPending;

  /// No description provided for @vaultDiscoveryVdkVersion.
  ///
  /// In en, this message translates to:
  /// **'Current Discovery key version: v{version}'**
  String vaultDiscoveryVdkVersion(int version);

  /// No description provided for @vaultDiscoveryKeyVersion.
  ///
  /// In en, this message translates to:
  /// **'Recipient key v{version}'**
  String vaultDiscoveryKeyVersion(int version);

  /// No description provided for @vaultMemberYou.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get vaultMemberYou;

  /// No description provided for @vaultMemberActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get vaultMemberActive;

  /// No description provided for @vaultMemberPending.
  ///
  /// In en, this message translates to:
  /// **'Removal pending'**
  String get vaultMemberPending;

  /// No description provided for @vaultMemberRotating.
  ///
  /// In en, this message translates to:
  /// **'Securing access — Vault remains available'**
  String get vaultMemberRotating;

  /// No description provided for @vaultMemberBlockedLast.
  ///
  /// In en, this message translates to:
  /// **'Blocked — last capable Member'**
  String get vaultMemberBlockedLast;

  /// No description provided for @vaultMemberRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get vaultMemberRemove;

  /// No description provided for @vaultMemberRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove organization Member?'**
  String get vaultMemberRemoveTitle;

  /// No description provided for @vaultMemberRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Removing {name} affects every Vault they can access. Access remains active until all required key rotations commit.'**
  String vaultMemberRemoveBody(String name);

  /// No description provided for @vaultMemberRemovalStarted.
  ///
  /// In en, this message translates to:
  /// **'Removal started. This Vault remains available while rotations finish.'**
  String get vaultMemberRemovalStarted;

  /// No description provided for @vaultMembersLoadError.
  ///
  /// In en, this message translates to:
  /// **'Member status could not be loaded.'**
  String get vaultMembersLoadError;

  /// No description provided for @vaultMemberForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage organization Members.'**
  String get vaultMemberForbidden;

  /// No description provided for @vaultMemberProtected.
  ///
  /// In en, this message translates to:
  /// **'This Member cannot be removed.'**
  String get vaultMemberProtected;

  /// No description provided for @vaultMemberNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get vaultMemberNetworkError;

  /// No description provided for @vaultMetadataConflict.
  ///
  /// In en, this message translates to:
  /// **'This Vault changed on another device. Review the latest values and try again.'**
  String get vaultMetadataConflict;

  /// No description provided for @vaultMetadataCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Vault settings could not be verified. No changes were saved.'**
  String get vaultMetadataCorrupt;

  /// No description provided for @entryTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get entryTabHistory;

  /// No description provided for @entryHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No previous versions'**
  String get entryHistoryEmpty;

  /// No description provided for @entryHistoryLoadError.
  ///
  /// In en, this message translates to:
  /// **'Encrypted history could not be loaded or verified.'**
  String get entryHistoryLoadError;

  /// No description provided for @entryHistoryVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {revision}'**
  String entryHistoryVersion(String revision);

  /// No description provided for @entryHistoryActor.
  ///
  /// In en, this message translates to:
  /// **'{actor} · {time}'**
  String entryHistoryActor(String actor, String time);

  /// No description provided for @entryHistoryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load older versions'**
  String get entryHistoryLoadMore;

  /// No description provided for @entryHistoryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get entryHistoryCurrent;

  /// No description provided for @entryHistoryReveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get entryHistoryReveal;

  /// No description provided for @entryHistoryHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get entryHistoryHide;

  /// No description provided for @entryHistoryDecrypting.
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get entryHistoryDecrypting;

  /// No description provided for @entryHistoryRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get entryHistoryRestore;

  /// No description provided for @entryHistoryRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get entryHistoryRestoring;

  /// No description provided for @entryHistoryRestored.
  ///
  /// In en, this message translates to:
  /// **'Historical content restored as a new current version.'**
  String get entryHistoryRestored;

  /// No description provided for @entryHistoryDecryptError.
  ///
  /// In en, this message translates to:
  /// **'Could not decrypt this version. The vault may be locked.'**
  String get entryHistoryDecryptError;

  /// No description provided for @entryHistoryRestoreError.
  ///
  /// In en, this message translates to:
  /// **'Could not restore this version.'**
  String get entryHistoryRestoreError;

  /// No description provided for @entryHistoryOperationCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get entryHistoryOperationCreated;

  /// No description provided for @entryHistoryOperationUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get entryHistoryOperationUpdated;

  /// No description provided for @entryHistoryOperationArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get entryHistoryOperationArchived;

  /// No description provided for @entryHistoryOperationRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get entryHistoryOperationRestored;

  /// No description provided for @entryHistoryOperationDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get entryHistoryOperationDeleted;

  /// No description provided for @entryHistoryMemberActor.
  ///
  /// In en, this message translates to:
  /// **'Member: {name}'**
  String entryHistoryMemberActor(String name);

  /// No description provided for @entryHistoryAgentActor.
  ///
  /// In en, this message translates to:
  /// **'Agent: {name}'**
  String entryHistoryAgentActor(String name);

  /// No description provided for @entryHistorySystemActor.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get entryHistorySystemActor;

  /// No description provided for @entryHistorySensitiveWarning.
  ///
  /// In en, this message translates to:
  /// **'Historical versions may contain previous passwords and TOTP seeds.'**
  String get entryHistorySensitiveWarning;

  /// No description provided for @entryHistoryLocked.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app to decrypt this version.'**
  String get entryHistoryLocked;

  /// Settings drawer item — set up TOTP two-factor auth
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get settingsTwoFactor;

  /// No description provided for @entryCardholderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Cardholder name'**
  String get entryCardholderNameLabel;

  /// No description provided for @entryCardNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Card number'**
  String get entryCardNumberLabel;

  /// No description provided for @entryExpiryMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry month'**
  String get entryExpiryMonthLabel;

  /// No description provided for @entryExpiryYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry year'**
  String get entryExpiryYearLabel;

  /// No description provided for @entryBillingAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Billing address (optional)'**
  String get entryBillingAddressLabel;

  /// No description provided for @settingsOrganizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get settingsOrganizationTitle;

  /// No description provided for @settingsGeneralTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralTitle;

  /// No description provided for @settingsGeneralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organization profile'**
  String get settingsGeneralSubtitle;

  /// No description provided for @settingsTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get settingsTeam;

  /// No description provided for @settingsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get settingsPermissions;

  /// No description provided for @settingsAuditLogs.
  ///
  /// In en, this message translates to:
  /// **'Audit logs'**
  String get settingsAuditLogs;

  /// No description provided for @settingsBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get settingsBilling;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsDataImport.
  ///
  /// In en, this message translates to:
  /// **'Data import'**
  String get settingsDataImport;

  /// No description provided for @settingsActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get settingsActionsTitle;

  /// No description provided for @settingsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'You can view these settings, but only an organization manager can change them.'**
  String get settingsReadOnly;

  /// No description provided for @settingsErrorConflict.
  ///
  /// In en, this message translates to:
  /// **'The resource changed or is still in use. Refresh and try again.'**
  String get settingsErrorConflict;

  /// No description provided for @teamScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get teamScreenTitle;

  /// No description provided for @teamScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Members and pending invitations'**
  String get teamScreenSubtitle;

  /// No description provided for @teamSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search members and invitations'**
  String get teamSearchHint;

  /// No description provided for @teamFilterMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get teamFilterMembers;

  /// No description provided for @teamFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending invitations'**
  String get teamFilterPending;

  /// No description provided for @teamInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get teamInvite;

  /// No description provided for @teamInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite a member'**
  String get teamInviteTitle;

  /// No description provided for @teamSeatUsage.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} seats used'**
  String teamSeatUsage(int used, int limit);

  /// No description provided for @teamSeatUsageLabel.
  ///
  /// In en, this message translates to:
  /// **'Seat usage'**
  String get teamSeatUsageLabel;

  /// No description provided for @teamSeatUsageValue.
  ///
  /// In en, this message translates to:
  /// **'{used} / {limit}'**
  String teamSeatUsageValue(int used, int limit);

  /// No description provided for @teamSeatsAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} available'**
  String teamSeatsAvailable(int count);

  /// No description provided for @teamSeatsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Seat usage is unavailable.'**
  String get teamSeatsUnavailable;

  /// No description provided for @teamManageSeats.
  ///
  /// In en, this message translates to:
  /// **'Manage seats'**
  String get teamManageSeats;

  /// No description provided for @teamSeatLimitReached.
  ///
  /// In en, this message translates to:
  /// **'The organization has no available seats.'**
  String get teamSeatLimitReached;

  /// Title shown instead of the invite form when every organization seat is occupied
  ///
  /// In en, this message translates to:
  /// **'No seats available'**
  String get teamNoSeatsTitle;

  /// Guidance shown when the invite form is blocked because no organization seat is available
  ///
  /// In en, this message translates to:
  /// **'Manage organization seats before inviting another member.'**
  String get teamNoSeatsBody;

  /// No description provided for @teamEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get teamEmailLabel;

  /// No description provided for @teamRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial role'**
  String get teamRoleLabel;

  /// No description provided for @teamSendInvitation.
  ///
  /// In en, this message translates to:
  /// **'Send invitation'**
  String get teamSendInvitation;

  /// No description provided for @teamInvitationSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent.'**
  String get teamInvitationSent;

  /// No description provided for @teamInvitationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Invitation cancelled.'**
  String get teamInvitationCancelled;

  /// No description provided for @teamInvitationResent.
  ///
  /// In en, this message translates to:
  /// **'Invitation resent with a new link.'**
  String get teamInvitationResent;

  /// No description provided for @teamInvitationRoleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Invitation role updated.'**
  String get teamInvitationRoleUpdated;

  /// No description provided for @teamMemberRolesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Member roles updated.'**
  String get teamMemberRolesUpdated;

  /// No description provided for @teamInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get teamInvalidEmail;

  /// No description provided for @teamNoInvitationRoles.
  ///
  /// In en, this message translates to:
  /// **'No invitation-safe roles are available.'**
  String get teamNoInvitationRoles;

  /// No description provided for @teamEmpty.
  ///
  /// In en, this message translates to:
  /// **'No organization members found.'**
  String get teamEmpty;

  /// No description provided for @teamNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching people or invitations.'**
  String get teamNoMatches;

  /// No description provided for @teamOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get teamOwner;

  /// No description provided for @teamPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get teamPending;

  /// No description provided for @teamRoleCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 role} other{{count} roles}}'**
  String teamRoleCount(int count);

  /// No description provided for @teamMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get teamMemberTitle;

  /// No description provided for @teamJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined {date}'**
  String teamJoined(String date);

  /// No description provided for @teamRolesTitle.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get teamRolesTitle;

  /// No description provided for @teamRolesHint.
  ///
  /// In en, this message translates to:
  /// **'Roles control organization administration. They do not grant access to encrypted Vault contents.'**
  String get teamRolesHint;

  /// No description provided for @teamSaveRoles.
  ///
  /// In en, this message translates to:
  /// **'Save roles'**
  String get teamSaveRoles;

  /// No description provided for @teamAtLeastOneRole.
  ///
  /// In en, this message translates to:
  /// **'Every member must keep at least one role.'**
  String get teamAtLeastOneRole;

  /// No description provided for @teamMemberReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This member\'s roles cannot be changed by your account.'**
  String get teamMemberReadOnly;

  /// No description provided for @teamInvitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending invitation'**
  String get teamInvitationTitle;

  /// No description provided for @teamInvitedBy.
  ///
  /// In en, this message translates to:
  /// **'Invited by {name}'**
  String teamInvitedBy(String name);

  /// No description provided for @teamSentAt.
  ///
  /// In en, this message translates to:
  /// **'Sent {date}'**
  String teamSentAt(String date);

  /// No description provided for @teamExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String teamExpiresAt(String date);

  /// No description provided for @teamResend.
  ///
  /// In en, this message translates to:
  /// **'Resend invitation'**
  String get teamResend;

  /// No description provided for @teamResendAvailable.
  ///
  /// In en, this message translates to:
  /// **'Resend available {date}'**
  String teamResendAvailable(String date);

  /// No description provided for @teamCancelInvitation.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation'**
  String get teamCancelInvitation;

  /// No description provided for @teamCancelInvitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this invitation?'**
  String get teamCancelInvitationTitle;

  /// No description provided for @teamCancelInvitationBody.
  ///
  /// In en, this message translates to:
  /// **'The current invitation link will stop working and its reserved seat will be released.'**
  String get teamCancelInvitationBody;

  /// No description provided for @teamCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get teamCancel;

  /// No description provided for @teamConfirmCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation'**
  String get teamConfirmCancel;

  /// No description provided for @permissionsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsScreenTitle;

  /// No description provided for @permissionsScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organization roles and administrative access'**
  String get permissionsScreenSubtitle;

  /// No description provided for @permissionsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create role'**
  String get permissionsCreate;

  /// No description provided for @permissionsCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create role'**
  String get permissionsCreateTitle;

  /// No description provided for @permissionsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get permissionsEditTitle;

  /// No description provided for @permissionsRoleName.
  ///
  /// In en, this message translates to:
  /// **'Role name'**
  String get permissionsRoleName;

  /// No description provided for @permissionsRoleNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Vault manager'**
  String get permissionsRoleNameHint;

  /// No description provided for @permissionsPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Administrative permissions'**
  String get permissionsPermissionTitle;

  /// No description provided for @permissionsPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Permissions do not provide cryptographic access to Vault contents.'**
  String get permissionsPermissionHint;

  /// No description provided for @permissionsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get permissionsSystem;

  /// No description provided for @permissionsAssignedMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 assigned member} other{{count} assigned members}}'**
  String permissionsAssignedMembers(int count);

  /// No description provided for @permissionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No organization roles found.'**
  String get permissionsEmpty;

  /// No description provided for @permissionsCreated.
  ///
  /// In en, this message translates to:
  /// **'Role created.'**
  String get permissionsCreated;

  /// No description provided for @permissionsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Role updated.'**
  String get permissionsUpdated;

  /// No description provided for @permissionsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Role deleted.'**
  String get permissionsDeleted;

  /// No description provided for @permissionsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete role'**
  String get permissionsDelete;

  /// No description provided for @permissionsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this role?'**
  String get permissionsDeleteTitle;

  /// No description provided for @permissionsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting an unassigned custom role cannot be undone.'**
  String get permissionsDeleteBody;

  /// No description provided for @permissionsDeleteBlocked.
  ///
  /// In en, this message translates to:
  /// **'Remove this role from every member before deleting it.'**
  String get permissionsDeleteBlocked;

  /// No description provided for @permissionsSystemReadOnly.
  ///
  /// In en, this message translates to:
  /// **'System roles are managed by Palladin and cannot be edited.'**
  String get permissionsSystemReadOnly;

  /// No description provided for @permissionsRoleReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This role is outside your assignable permission scope and is read-only.'**
  String get permissionsRoleReadOnly;

  /// No description provided for @permissionsSave.
  ///
  /// In en, this message translates to:
  /// **'Save role'**
  String get permissionsSave;

  /// No description provided for @settingsSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurityTitle;

  /// No description provided for @settingsSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Authentication and account protection'**
  String get settingsSecuritySubtitle;

  /// No description provided for @settingsSecurityPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Rotate the master password used to unlock your account.'**
  String get settingsSecurityPasswordHint;

  /// No description provided for @settingsSecurityTwoFactorHint.
  ///
  /// In en, this message translates to:
  /// **'Protect password sign-in with a time-based one-time code.'**
  String get settingsSecurityTwoFactorHint;

  /// No description provided for @settingsSecurityOAuth.
  ///
  /// In en, this message translates to:
  /// **'Password and two-factor settings are managed by your sign-in provider.'**
  String get settingsSecurityOAuth;

  /// No description provided for @settingsDataImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Data import'**
  String get settingsDataImportTitle;

  /// No description provided for @settingsDataImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bring credentials from another password manager'**
  String get settingsDataImportSubtitle;

  /// No description provided for @settingsDataImportBody.
  ///
  /// In en, this message translates to:
  /// **'Choose an export file and a destination Vault. The file is parsed and encrypted on this device before any data is sent.'**
  String get settingsDataImportBody;

  /// No description provided for @settingsDataImportAction.
  ///
  /// In en, this message translates to:
  /// **'Choose Vault and file'**
  String get settingsDataImportAction;

  /// No description provided for @settingsBillingTitle.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get settingsBillingTitle;

  /// No description provided for @settingsBillingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plan and organization seats'**
  String get settingsBillingSubtitle;

  /// No description provided for @settingsBillingComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Billing is coming soon'**
  String get settingsBillingComingSoon;

  /// No description provided for @settingsBillingComingSoonBody.
  ///
  /// In en, this message translates to:
  /// **'Plan management is not available yet. Your current access remains unchanged.'**
  String get settingsBillingComingSoonBody;

  /// No description provided for @permissionAddUser.
  ///
  /// In en, this message translates to:
  /// **'Invite members'**
  String get permissionAddUser;

  /// No description provided for @permissionOrganizationManagement.
  ///
  /// In en, this message translates to:
  /// **'Manage organization'**
  String get permissionOrganizationManagement;

  /// No description provided for @permissionVaultCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Vaults'**
  String get permissionVaultCreate;

  /// No description provided for @permissionVaultManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Vaults'**
  String get permissionVaultManage;

  /// No description provided for @permissionAgentManage.
  ///
  /// In en, this message translates to:
  /// **'Manage agents'**
  String get permissionAgentManage;

  /// No description provided for @permissionGrantManage.
  ///
  /// In en, this message translates to:
  /// **'Manage grants'**
  String get permissionGrantManage;

  /// No description provided for @permissionAuditView.
  ///
  /// In en, this message translates to:
  /// **'View audit logs'**
  String get permissionAuditView;

  /// No description provided for @permissionMultipleVaults.
  ///
  /// In en, this message translates to:
  /// **'Multiple Vaults'**
  String get permissionMultipleVaults;

  /// No description provided for @permissionReadApiKey.
  ///
  /// In en, this message translates to:
  /// **'View API keys'**
  String get permissionReadApiKey;

  /// No description provided for @permissionWriteApiKey.
  ///
  /// In en, this message translates to:
  /// **'Manage API keys'**
  String get permissionWriteApiKey;

  /// No description provided for @settingsGrantManageCutoverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Grant-management access cannot be changed yet. No role changes were saved.'**
  String get settingsGrantManageCutoverUnavailable;

  /// No description provided for @privacyManageChoices.
  ///
  /// In en, this message translates to:
  /// **'Manage choices'**
  String get privacyManageChoices;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional consents are voluntary. You can change them later in Privacy settings.'**
  String get privacySubtitle;

  /// No description provided for @privacyAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Product analytics'**
  String get privacyAnalytics;

  /// No description provided for @privacyMarketing.
  ///
  /// In en, this message translates to:
  /// **'Email marketing'**
  String get privacyMarketing;

  /// No description provided for @privacyContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get privacyContinue;

  /// No description provided for @privacyLoadError.
  ///
  /// In en, this message translates to:
  /// **'Privacy choices could not be loaded. Analytics stays off.'**
  String get privacyLoadError;

  /// No description provided for @privacyConflictError.
  ///
  /// In en, this message translates to:
  /// **'Privacy choices changed on another device. Review the current choices and save again to confirm.'**
  String get privacyConflictError;

  /// No description provided for @privacySaveError.
  ///
  /// In en, this message translates to:
  /// **'The choice could not be confirmed. Analytics in this app stays off. Retry or continue using Palladin.'**
  String get privacySaveError;

  /// No description provided for @privacyMarketingSaveError.
  ///
  /// In en, this message translates to:
  /// **'The choice could not be confirmed. Retry or continue using Palladin.'**
  String get privacyMarketingSaveError;

  /// No description provided for @privacyNoticeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Saving these optional consents is not available yet. You can continue with essential features.'**
  String get privacyNoticeUnavailable;

  /// No description provided for @privacyLocalActivation.
  ///
  /// In en, this message translates to:
  /// **'Account consent applies to web and mobile. Analytics also requires activation on each browser or mobile installation. Withdrawing consent disables it across your devices.'**
  String get privacyLocalActivation;

  /// No description provided for @privacySaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get privacySaving;

  /// No description provided for @privacySaved.
  ///
  /// In en, this message translates to:
  /// **'Privacy choice saved'**
  String get privacySaved;

  /// No description provided for @privacyRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry saving'**
  String get privacyRetry;

  /// No description provided for @privacyUnknown.
  ///
  /// In en, this message translates to:
  /// **'No choice recorded'**
  String get privacyUnknown;

  /// No description provided for @privacyGranted.
  ///
  /// In en, this message translates to:
  /// **'Account consent granted'**
  String get privacyGranted;

  /// No description provided for @privacyDenied.
  ///
  /// In en, this message translates to:
  /// **'Consent declined'**
  String get privacyDenied;

  /// No description provided for @privacyWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Consent withdrawn'**
  String get privacyWithdrawn;

  /// No description provided for @privacyOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your privacy'**
  String get privacyOnboardingTitle;

  /// No description provided for @privacyEssential.
  ///
  /// In en, this message translates to:
  /// **'Essential'**
  String get privacyEssential;

  /// No description provided for @privacyAlwaysActive.
  ///
  /// In en, this message translates to:
  /// **'Always active'**
  String get privacyAlwaysActive;

  /// No description provided for @privacyEssentialDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable core features and help protect your account.'**
  String get privacyEssentialDescription;

  /// No description provided for @privacyAnalyticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Optional measurements of how you use app features.'**
  String get privacyAnalyticsDescription;

  /// No description provided for @privacyMarketingDescription.
  ///
  /// In en, this message translates to:
  /// **'Palladin news and offers by email.'**
  String get privacyMarketingDescription;

  /// No description provided for @privacyAcceptAll.
  ///
  /// In en, this message translates to:
  /// **'Accept all'**
  String get privacyAcceptAll;

  /// No description provided for @privacySaveChoice.
  ///
  /// In en, this message translates to:
  /// **'Save choice'**
  String get privacySaveChoice;

  /// No description provided for @privacyDetails.
  ///
  /// In en, this message translates to:
  /// **'Consent details'**
  String get privacyDetails;

  /// No description provided for @privacyAnalyticsNotice.
  ///
  /// In en, this message translates to:
  /// **'With your consent, we use PostHog EU to measure how Palladin features are used and improve the app. We do not collect vault or form contents, passwords or keys, or record sessions. You can withdraw consent in Privacy settings.'**
  String get privacyAnalyticsNotice;

  /// No description provided for @privacyMarketingNotice.
  ///
  /// In en, this message translates to:
  /// **'With your consent, we will send you emails with Palladin news and offers. Essential transactional, account and security messages are sent independently of this consent. You can withdraw consent in Privacy settings.'**
  String get privacyMarketingNotice;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
