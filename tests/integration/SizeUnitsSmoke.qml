// Real binary-unit progress + cancellation proof, without replacing 0 A.D.
// while the user is installing/using it. Refuses an already installed test app.
import QtQuick

CancelSmoke {
    testId: "com.onepassword.OnePassword"
    waitForPayload: true
}
