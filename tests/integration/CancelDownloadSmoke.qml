// Opt-in VM test: cancel an actual app payload after at least 64 KiB arrives.
// Refuses preinstalled 0 A.D.; never removes it or any existing app/data.
import QtQuick

CancelSmoke {
    testId: "com.play0ad.zeroad"
    waitForPayload: true
}
