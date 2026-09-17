#pragma once
#include <QList>
#include <QLocale>

// Recent actual network bytes, never a rate inferred from progress/estimates.
// The caller also samples while idle so a stalled connection decays to zero.
class DownloadRate {
public:
    double sample(qint64 milliseconds, quint64 bytes, bool downloading) {
        if (!downloading || !m_downloading || (!m_samples.isEmpty()
            && (milliseconds < m_samples.last().time || bytes < m_samples.last().bytes))) {
            m_samples.clear();
            m_samples.append({milliseconds, bytes});
            m_downloading = downloading;
            return 0;
        }
        if (milliseconds == m_samples.last().time) m_samples.last().bytes = bytes;
        else m_samples.append({milliseconds, bytes});
        while (m_samples.size() > 2 && m_samples[1].time <= milliseconds - 2000)
            m_samples.removeFirst();
        const auto elapsed = milliseconds - m_samples.first().time;
        return elapsed >= 100 ? double(bytes - m_samples.first().bytes) * 1000 / elapsed : 0;
    }
    static QString display(double bytesPerSecond) {
        return QLocale().toString(bytesPerSecond / 1000000, 'f', 2) + " MB/s";
    }
private:
    struct Sample { qint64 time; quint64 bytes; };
    QList<Sample> m_samples;
    bool m_downloading = false;
};
